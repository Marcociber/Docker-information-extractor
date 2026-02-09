#!/usr/bin/env python3
import docker
import subprocess
import json
import sys
import os
import shutil
import time
import threading
from datetime import datetime, timedelta
from pathlib import Path

class SecurityInfoExtractor:
    def __init__(self):
        self.client = docker.from_env()
        self.containers = self.detect_containers()
        
        # Crear carpeta con formato info_results_{dia}_{hora}
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.results_dir = f'info_results_{timestamp}'
        os.makedirs(self.results_dir, exist_ok=True)
        
        print(f"Resultados se guardarán en: {self.results_dir}")
        
        # Iniciar limpieza automática en segundo plano
        self.start_cleanup_thread()
    
    def start_cleanup_thread(self):
        """Inicia un hilo para limpiar carpetas antiguas cada hora"""
        def cleanup_old_folders():
            while True:
                try:
                    self.cleanup_old_results()
                except Exception as e:
                    print(f"Error en limpieza automática: {e}")
                # Esperar 1 hora antes de la siguiente limpieza
                time.sleep(3600)
        
        # Iniciar el hilo en segundo plano
        cleanup_thread = threading.Thread(target=cleanup_old_folders, daemon=True)
        cleanup_thread.start()
    
    def cleanup_old_results(self):
        """Elimina carpetas de resultados con más de 48 horas"""
        try:
            now = datetime.now()
            max_age = timedelta(hours=48)
            
            # Buscar todas las carpetas que comiencen con 'info_results_'
            current_dir = os.getcwd()
            for item in os.listdir(current_dir):
                if os.path.isdir(item) and item.startswith('info_results_'):
                    folder_path = os.path.join(current_dir, item)
                    
                    try:
                        # Extraer fecha del nombre de carpeta
                        # Formato: info_results_YYYYMMDD_HHMMSS
                        date_str = item.replace('info_results_', '')
                        folder_date = datetime.strptime(date_str, "%Y%m%d_%H%M%S")
                        folder_age = now - folder_date
                        
                        if folder_age > max_age:
                            print(f"Eliminando carpeta antigua: {item} ({folder_age.days}d {folder_age.seconds//3600}h)")
                            shutil.rmtree(folder_path)
                    except ValueError:
                        # Si no tiene formato de fecha correcto, ignorar
                        continue
        except Exception as e:
            print(f"Error al limpiar carpetas antiguas: {e}")
    
    def detect_containers(self):
        """Detecta automáticamente los contenedores disponibles"""
        containers_dict = {}
        try:
            all_containers = self.client.containers.list(all=True)
            print(f"Contenedores detectados: {len(all_containers)}")
            
            for i, container in enumerate(all_containers):
                container_name = container.name
                os_name = self.guess_os_from_container(container)
                
                if os_name and os_name != "unknown":
                    key = os_name.lower()
                    if key in containers_dict:
                        key = f"{key}_{i}"
                else:
                    key = container_name.replace('-', '_').replace('.', '_').lower()
                
                containers_dict[key] = container_name
                print(f"  [{key}] -> {container_name} ({container.status})")
            
            return containers_dict
        except Exception as e:
            print(f"Error: {e}")
            return {}
    
    def guess_os_from_container(self, container):
        """Determina el sistema operativo del contenedor"""
        try:
            # Verificar etiquetas de imagen
            for tag in container.image.tags or []:
                tag_lower = tag.lower()
                for os_name in ['ubuntu', 'debian', 'fedora', 'centos', 'alpine', 'rocky']:
                    if os_name in tag_lower:
                        return os_name
            
            # Comprobar /etc/os-release
            try:
                os_info = container.exec_run(['cat', '/etc/os-release'])
                if os_info.exit_code == 0:
                    output = os_info.output.decode('utf-8', errors='ignore').lower()
                    for os_name in ['ubuntu', 'debian', 'fedora', 'centos', 'alpine']:
                        if os_name in output:
                            return os_name
            except:
                pass
            
            # Verificar gestores de paquetes
            package_managers = {
                'apt-get': 'debian',
                'dpkg': 'debian', 
                'yum': 'centos',
                'dnf': 'fedora',
                'apk': 'alpine'
            }
            
            for cmd, os_name in package_managers.items():
                try:
                    if container.exec_run(['which', cmd]).exit_code == 0:
                        return os_name
                except:
                    continue
            
            return "unknown"
        except:
            return "unknown"
    
    def run_safe_command(self, container, cmd):
        """Ejecuta un comando de forma segura"""
        try:
            result = container.exec_run(['sh', '-c', cmd])
            if result.exit_code == 0:
                output = result.output.decode('utf-8', errors='ignore').strip()
                return output if output else ""
            return ""
        except:
            return ""
    
    def get_container_ip_simple(self, container):
        """Obtiene IP del contenedor"""
        try:
            # Método 1: hostname -i
            ip_result = self.run_safe_command(container, 'hostname -i 2>/dev/null')
            if ip_result:
                for ip in ip_result.split():
                    if len(ip) > 6 and '127.' not in ip and ip.count('.') == 3:
                        return ip
            
            # Método 2: ip addr show
            ip = self.run_safe_command(container, 
                'ip addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | head -1 | awk \'{print $2}\' | cut -d/ -f1')
            if ip and ip.count('.') == 3:
                return ip
            
            # Método 3: Inspección Docker
            try:
                networks = container.attrs.get('NetworkSettings', {}).get('Networks', {})
                for net_info in networks.values():
                    ip_addr = net_info.get('IPAddress', '')
                    if ip_addr and ip_addr.count('.') == 3 and '127.' not in ip_addr:
                        return ip_addr
            except:
                pass
            
            return "No IP"
        except:
            return "No IP"
    
    def get_package_count_simple(self, container, os_name):
        """Obtiene conteo de paquetes"""
        try:
            os_lower = os_name.lower()
            
            if 'ubuntu' in os_lower or 'debian' in os_lower:
                result = self.run_safe_command(container, 'dpkg-query -f \'.\n\' -W 2>/dev/null | wc -l')
                if result and result.isdigit():
                    return result
            
            elif 'fedora' in os_lower or 'centos' in os_lower or 'rocky' in os_lower:
                cmd_results = []
                for cmd in ['rpm -qa 2>/dev/null | wc -l', 'rpm -qa --quiet 2>/dev/null | wc -l']:
                    result = self.run_safe_command(container, cmd)
                    if result and result.isdigit():
                        cmd_results.append(int(result))
                
                result = self.run_safe_command(container, 'dnf list installed 2>/dev/null 2>&1 | tail -n +2 | wc -l')
                if result and result.isdigit():
                    cmd_results.append(int(result))
                
                if cmd_results:
                    return str(max(cmd_results))
            
            elif 'alpine' in os_lower:
                result = self.run_safe_command(container, 'apk info 2>/dev/null | wc -l')
                if result and result.isdigit():
                    return result
            
            return "N/A"
        except:
            return "N/A"
    
    def get_open_ports_simple(self, container):
        """Obtiene puertos abiertos"""
        try:
            for cmd in [
                'netstat -tln 2>/dev/null | grep LISTEN | awk \'{print $4}\' | awk -F: \'{print $NF}\'',
                'ss -tln 2>/dev/null | grep LISTEN | awk \'{print $4}\' | awk -F: \'{print $NF}\''
            ]:
                ports_result = self.run_safe_command(container, cmd)
                if ports_result:
                    ports = []
                    for line in ports_result.split('\n'):
                        port = line.strip()
                        if port and port.isdigit() and port not in ports:
                            ports.append(port)
                    return sorted(ports)
            return []
        except:
            return []
    
    def get_basic_info(self, container_name):
        """Obtiene información esencial del contenedor"""
        try:
            container = self.client.containers.get(container_name)
        except:
            return {"error": "Contenedor no encontrado"}
        
        info = {}
        
        # Información básica del sistema
        os_result = self.run_safe_command(container, 'cat /etc/os-release 2>/dev/null | grep -i "PRETTY_NAME" | head -1')
        info['os'] = os_result.split('=')[1].strip('"') if os_result and '=' in os_result else "Desconocido"
        
        info['kernel'] = self.run_safe_command(container, 'uname -r') or "N/A"
        
        # Uptime
        uptime_result = self.run_safe_command(container, 'cat /proc/uptime 2>/dev/null')
        if uptime_result:
            try:
                seconds = float(uptime_result.split()[0])
                hours = int(seconds // 3600)
                minutes = int((seconds % 3600) // 60)
                info['uptime'] = f"{hours}h {minutes}m"
            except:
                info['uptime'] = "N/A"
        else:
            info['uptime'] = "N/A"
        
        # Usuarios y procesos
        for cmd, key in [
            ('cat /etc/passwd 2>/dev/null | wc -l', 'usuarios'),
            ('ps -e --no-headers 2>/dev/null | wc -l', 'procesos'),
            ('grep -Ev ":(/usr/sbin/nologin|/bin/false|/sbin/nologin)" /etc/passwd 2>/dev/null | wc -l', 'usuarios_con_shell')
        ]:
            result = self.run_safe_command(container, cmd)
            info[key] = result if result and result.isdigit() else "N/A"
        
        # Paquetes y puertos
        info['paquetes'] = self.get_package_count_simple(container, info.get('os', ''))
        
        ports = self.get_open_ports_simple(container)
        info['puertos_abiertos'] = ', '.join(ports) if ports else "Ninguno"
        
        # IP y SSH
        info['ip'] = self.get_container_ip_simple(container)
        info['ssh'] = "Sí" if self.run_safe_command(container, 'which sshd 2>/dev/null || ls /usr/sbin/sshd 2>/dev/null') else "No"
        
        return info
    
    def test_ping_between_containers(self, container1_name, container2_ip):
        """Prueba ping entre dos contenedores"""
        try:
            if not container2_ip or container2_ip == "No IP" or container2_ip.count('.') != 3:
                return "NO IP"
            
            container1 = self.client.containers.get(container1_name)
            result = self.run_safe_command(container1, 
                f'timeout 2 ping -c 1 {container2_ip} >/dev/null 2>&1 && echo "OK" || echo "FAIL"')
            return "OK" if result == "OK" else "FAIL"
        except:
            return "FAIL"
    
    def generate_report(self):
        """Genera reporte completo"""
        print("\n" + "=" * 60)
        print("ANALISIS COMPLETO - DETECCION AUTOMATICA DE CONTENEDORES")
        print("=" * 60)
        
        if not self.containers:
            print("\n¡No se encontraron contenedores!")
            return None
        
        report_data = {
            'timestamp': datetime.now().isoformat(),
            'host': subprocess.getoutput('hostname'),
            'docker_version': subprocess.getoutput('docker --version'),
            'python_version': sys.version.split()[0],
            'results_folder': self.results_dir,
            'containers': {}
        }
        
        print(f"\nAnalizando {len(self.containers)} contenedores...")
        
        all_info = {}
        for system, container_name in self.containers.items():
            print(f"\n[{system.upper()}] {container_name}")
            print("-" * 30)
            
            try:
                container = self.client.containers.get(container_name)
                if container.status != 'running':
                    print(f"  No está corriendo ({container.status})")
                    continue
                
                print(f"  Contenedor: {container_name}")
                print(f"  ID: {container.short_id}")
                print(f"  Estado: {container.status}")
                print(f"  Imagen: {container.image.tags[0] if container.image.tags else str(container.image)}")
                
                container_info = self.get_basic_info(container_name)
                all_info[system] = {'container': container, 'info': container_info, 'name': container_name}
                
                # Mostrar información
                for key, label in [
                    ('os', 'Sistema'), ('kernel', 'Kernel'), ('uptime', 'Uptime'),
                    ('usuarios', 'Usuarios'), ('usuarios_con_shell', 'Usuarios con shell'),
                    ('procesos', 'Procesos'), ('paquetes', 'Paquetes instalados'),
                    ('puertos_abiertos', 'Puertos abiertos'), ('ip', 'IP'), ('ssh', 'SSH instalado')
                ]:
                    value = container_info.get(key, 'N/A')
                    if value != "N/A" or key in ['os', 'kernel', 'ip', 'ssh']:
                        print(f"  {label}: {value}")
                
                report_data['containers'][system] = {
                    'nombre': container_name,
                    'estado': container.status,
                    'imagen': container.image.tags[0] if container.image.tags else str(container.image),
                    'id': container.short_id,
                    'creado': container.attrs['Created'],
                    'informacion': container_info
                }
                
            except Exception as e:
                print(f"  Error: {str(e)[:50]}")
                all_info[system] = None
        
        # Test de conectividad
        running_containers = [data for data in all_info.values() if data]
        if len(running_containers) >= 2:
            print(f"\nTEST DE CONECTIVIDAD")
            print("-" * 40)
            
            connectivity = {}
            for system1, data1 in all_info.items():
                if not data1:
                    continue
                
                ip1 = data1['info'].get('ip', '')
                if not ip1 or ip1 == "No IP":
                    continue
                
                print(f"\nDesde {system1.upper()} ({ip1}):")
                connectivity[system1] = {}
                
                for system2, data2 in all_info.items():
                    if system1 == system2 or not data2:
                        continue
                    
                    ip2 = data2['info'].get('ip', '')
                    if not ip2 or ip2 == "No IP":
                        continue
                    
                    result = self.test_ping_between_containers(data1['name'], ip2)
                    print(f"  -> {system2}: {ip2} [{result}]")
                    connectivity[system1][system2] = result
        else:
            connectivity = {}
        
        report_data['connectivity'] = connectivity
        
        # Guardar reportes
        self.save_reports(report_data, connectivity)
        
        return report_data
    
    def save_reports(self, report_data, connectivity):
        """Guarda los reportes en archivos"""
        if not report_data.get('containers'):
            return
        
        # Guardar JSON principal
        json_file = os.path.join(self.results_dir, 'results.json')
        with open(json_file, 'w', encoding='utf-8') as f:
            json.dump(report_data, f, indent=2, ensure_ascii=False)
        
        # Guardar TXT principal
        txt_file = os.path.join(self.results_dir, 'results.txt')
        with open(txt_file, 'w', encoding='utf-8') as f:
            f.write("=" * 60 + "\n")
            f.write("ANALISIS COMPLETO - DETECCION AUTOMATICA DE CONTENEDORES\n")
            f.write("=" * 60 + "\n\n")
            
            f.write(f"Fecha: {report_data['timestamp']}\n")
            f.write(f"Host: {report_data['host']}\n")
            f.write(f"Docker: {report_data['docker_version']}\n")
            f.write(f"Carpeta de resultados: {report_data['results_folder']}\n\n")
            
            f.write("RESUMEN POR CONTENEDOR:\n")
            for system, data in report_data['containers'].items():
                f.write(f"\n[{system.upper()}]\n")
                f.write("-" * 40 + "\n")
                
                if 'error' in data.get('informacion', {}):
                    continue
                
                info = data['informacion']
                for key, label in [
                    ('nombre', 'Contenedor'), ('id', 'ID'), ('estado', 'Estado'),
                    ('imagen', 'Imagen'), ('os', 'Sistema'), ('kernel', 'Kernel'),
                    ('uptime', 'Uptime'), ('usuarios', 'Usuarios'), 
                    ('usuarios_con_shell', 'Usuarios con shell'), ('procesos', 'Procesos'),
                    ('paquetes', 'Paquetes instalados'), ('puertos_abiertos', 'Puertos abiertos'),
                    ('ip', 'IP'), ('ssh', 'SSH instalado')
                ]:
                    value = info.get(key) if key in info else data.get(key, 'N/A')
                    if value != "N/A":
                        f.write(f"{label}: {value}\n")
            
            f.write("\n" + "=" * 60 + "\n")
            f.write("CONECTIVIDAD\n")
            f.write("=" * 60 + "\n")
            
            if connectivity:
                for source, targets in connectivity.items():
                    if targets:
                        f.write(f"\n{source.upper()}:\n")
                        for target, status in targets.items():
                            f.write(f"  -> {target}: {status}\n")
        
        # Guardar también un archivo de metadatos
        metadata = {
            'generated_at': datetime.now().isoformat(),
            'folder_name': self.results_dir,
            'expires_at': (datetime.now() + timedelta(hours=48)).isoformat(),
            'containers_analyzed': len(report_data.get('containers', {}))
        }
        
        metadata_file = os.path.join(self.results_dir, 'metadata.json')
        with open(metadata_file, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)
        
        print(f"\nReportes guardados en: {self.results_dir}/")
        print(f"Estos resultados se eliminarán automáticamente después de 48 horas")
        
        # Mostrar archivos creados
        print(f"\nArchivos creados:")
        for file in os.listdir(self.results_dir):
            print(f"  - {file}")

if __name__ == "__main__":
    try:
        print("Iniciando análisis automático...")
        extractor = SecurityInfoExtractor()
        report = extractor.generate_report()
        
        if report:
            # Ejecutar limpieza inmediata al finalizar
            print("\nEjecutando limpieza de carpetas antiguas...")
            extractor.cleanup_old_results()
        
    except docker.errors.DockerException:
        print("\nError: Docker no está disponible")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)