# Docker-information-extractor

## 🐳 Contenedores Disponibles

### Ubuntu Target (`tfm_ubuntu`)
- **Imagen**: Ubuntu latest
- **IP**: 172.30.0.10
- **Puertos expuestos**: 
  - 8080 → 80 (Apache)
  - 2222 → 22 (SSH)
  - 445 → 445 (SMB)
- **Servicios**: Apache, SSH, Samba
- **Credenciales SSH**: root / password

### Debian Target (`tfm_debian`)
- **Imagen**: Debian latest
- **IP**: 172.30.0.20
- **Puertos expuestos**:
  - 8081 → 80 (Apache)
  - 2223 → 22 (SSH)
- **Servicios**: Apache, SSH
- **Credenciales SSH**: root / password

### Fedora Target (`tfm_fedora`)
- **Imagen**: Fedora latest
- **IP**: 172.30.0.30
- **Puertos expuestos**: Ninguno
- **Configuración**: Solo herramientas de red (sin servicios)
- **Herramientas**: nmap, net-tools, iputils, etc.

## 🚀 Instalación y Uso

### Prerrequisitos
- Docker y Docker Compose instalados
- Python 3.6+ (para info_collector.py)
- Bash (para scripts shell)
- Permisos de superusuario (sudo)

### Instalación Rápida

```bash
# Clonar el repositorio
git clone https://github.com/Marcociber/Docker-information-extractor
cd <directorio-del-proyecto>

# Dar permisos de ejecución a los scripts
chmod +x setup_containers.sh nmap_scanner.sh

# Ejecutar la configuración (requiere sudo)
sudo ./setup_containers.sh

# Pasos Detallados

### Iniciar los contenedores:
```bash
sudo docker compose up -d
```

### Verificar el estado:
```bash
sudo docker ps
```

### Ejecutar el recolector de información:
```bash
python3 info_collector.py
```

### Realizar escaneo de vulnerabilidades:
```bash
sudo ./nmap_scanner.sh
```

---

## 📊 Scripts Disponibles

### `setup_containers.sh`
Script principal de configuración que:
- Inicia los contenedores si no están corriendo
- Detecta y clasifica los contenedores por distribución
- Verifica la instalación de herramientas y servicios
- Configura resolución de nombres en `/etc/hosts`
- Realiza pruebas de conectividad
- Muestra un resumen completo de la configuración

**Uso:**
```bash
sudo ./setup_containers.sh
```

---

### `info_collector.py`
Recolector automático de información de los contenedores:
- Detecta contenedores automáticamente
- Obtiene información del sistema (OS, kernel, uptime)
- Cuenta usuarios, procesos y paquetes instalados
- Identifica puertos abiertos
- Prueba conectividad entre contenedores
- Genera reportes en JSON y TXT

**Características:**
- Limpieza automática de resultados antiguos (>48h)
- Genera carpetas únicas por ejecución (`info_results_YYYYMMDD_HHMMSS`)
- Reportes detallados en formato legible

**Uso:**
```bash
python3 info_collector.py
```

---

### `nmap_scanner.sh`
Escáner de vulnerabilidades automatizado:
- Ejecuta nmap con scripts de vulnerabilidad (`--script vuln`)
- Escanea todos los puertos (`-p-`)
- Detecta servicios y versiones (`-sV`)
- Realiza detección de OS y trazado de rutas (`-A`)
- Genera reportes estructurados en JSON y TXT
- Almacena resultados en `nmap_scans/nmap_scan_YYYYMMDD_HHMMSS/`

**Características:**
- Requiere permisos de superusuario
- Limpieza automática programada (48h)
- Estadísticas detalladas por escaneo
- Archivos raw de salida para análisis profundo

**Uso:**
```bash
sudo ./nmap_scanner.sh
```

---

## 🔧 Comandos Útiles

### Acceso a Contenedores
```bash
# Ubuntu
docker exec -it tfm_ubuntu bash

# Debian
docker exec -it tfm_debian bash

# Fedora
docker exec -it tfm_fedora bash
```

### Pruebas de Red
```bash
# Escaneo de red desde Ubuntu
docker exec tfm_ubuntu nmap -sP 172.30.0.0/24
docker exec tfm_ubuntu nmap -sV 172.30.0.0/24

# Pruebas SMB
docker exec tfm_ubuntu nmap --script smb-os-discovery -p 445 172.30.0.0/24
docker exec tfm_ubuntu smbclient -L //172.30.0.10/ -U guest

# Pruebas SSH
docker exec tfm_debian nmap --script ssh-auth-methods -p 22 172.30.0.0/24
```

### Gestión de Contenedores
```bash
# Detener todos los contenedores
docker compose down

# Ver logs
docker logs tfm_ubuntu
docker logs tfm_debian

# Reiniciar servicios
docker exec tfm_ubuntu service apache2 restart
docker exec tfm_ubuntu service smbd restart
docker exec tfm_ubuntu service ssh restart
```

---

## 📁 Estructura de Resultados

### Info Collector
```
info_results_YYYYMMDD_HHMMSS/
├── results.json          # Datos completos en JSON
├── results.txt           # Reporte legible
└── metadata.json         # Metadatos y expiración
```

### Nmap Scanner
```
nmap_scans/nmap_scan_YYYYMMDD_HHMMSS/
├── results/
│   ├── nmap_scanner.json    # Resultados estructurados
│   └── nmap_scanner.txt     # Reporte completo
├── logs/
│   └── scan_execution.log   # Log de ejecución
├── raw/                     # Salidas crudas de nmap
│   └── [container]_HHMMSS.txt
└── scan_metadata.txt        # Información del escaneo
```

---

## ⚠️ Consideraciones de Seguridad

- **Entorno Aislado:** Los contenedores están en una red Docker aislada (`172.30.0.0/24`)
- **Credenciales por Defecto:** Las contraseñas son débiles intencionalmente para prácticas
- **Servicios Vulnerables:** Algunos servicios pueden tener configuraciones inseguras
- **Uso Responsable:** Este laboratorio es **SOLO** para fines educativos y pruebas autorizadas
- **Limpieza Automática:** Los resultados se eliminan después de 48 horas

---

## 🔍 Solución de Problemas

### Los contenedores no inician
```bash
# Verificar logs
docker compose logs

# Reconstruir contenedores
docker compose down
docker compose up -d --build
```

### Scripts no tienen permisos
```bash
chmod +x *.sh
```

### Error de permisos Docker
```bash
# Añadir usuario al grupo docker
sudo usermod -aG docker $USER
# Cerrar sesión y volver a entrar
```

### Conflictos de puertos
Si los puertos `8080`, `8081`, `2222`, `2223` o `445` están ocupados, modifica el `docker-compose.yaml`.

---

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor:

1. Haz fork del proyecto
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

---

## 📄 Licencia

Este proyecto está licenciado bajo la **Licencia MIT** - ver el archivo `LICENSE` para más detalles.

---

## ✉️ Contacto

Para preguntas o sugerencias, por favor abre un **issue** en el repositorio.

---

> ⚠️ **ADVERTENCIA:** Este software es solo para fines educativos y de prueba en entornos controlados. No lo uses contra sistemas sin autorización explícita.
