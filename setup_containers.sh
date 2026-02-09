#!/bin/bash
set -e  # Detener script si hay error
echo "============================================"
echo "=== Configuración de Contenedores Docker ==="
echo "============================================"

# 1. Detectar contenedores existentes
echo -e "\nDetectando contenedores Docker existentes..."
CONTAINERS=($(docker ps --format "{{.Names}}" 2>/dev/null))

if [ ${#CONTAINERS[@]} -eq 0 ]; then
    echo "No se encontraron contenedores en ejecución."
    echo "Iniciando contenedores con docker compose..."
    docker compose up -d
    
    echo "Esperando a que los contenedores inicien (esto puede tardar unos minutos)..."
    echo "NOTA: Esto puede tomar 1-2 minutos mientras se instalan paquetes..."
    sleep 90  # Más tiempo para instalación inicial
    
    # Obtener la lista actualizada de contenedores
    CONTAINERS=($(docker ps --format "{{.Names}}" 2>/dev/null))
fi

if [ ${#CONTAINERS[@]} -eq 0 ]; then
    echo "ERROR: No se pudieron iniciar contenedores."
    exit 1
fi

echo "Contenedores detectados: ${#CONTAINERS[@]}"
printf '  %s\n' "${CONTAINERS[@]}"

# 2. Clasificar contenedores por distribución
echo -e "\nClasificando contenedores por distribución..."

UBUNTU_CONTAINERS=()
DEBIAN_CONTAINERS=()
FEDORA_CONTAINERS=()
OTHER_CONTAINERS=()

for container in "${CONTAINERS[@]}"; do
    echo -n "  Analizando $container: "
    
    # Intentar múltiples métodos para detectar distribución
    if docker exec "$container" sh -c "grep -qi 'ubuntu' /etc/os-release 2>/dev/null || grep -qi 'ubuntu' /etc/lsb-release 2>/dev/null" 2>/dev/null; then
        echo "Ubuntu"
        UBUNTU_CONTAINERS+=("$container")
    elif docker exec "$container" sh -c "grep -qi 'debian' /etc/os-release 2>/dev/null" 2>/dev/null; then
        echo "Debian"
        DEBIAN_CONTAINERS+=("$container")
    elif docker exec "$container" sh -c "grep -qi 'fedora' /etc/os-release 2>/dev/null" 2>/dev/null; then
        echo "Fedora"
        FEDORA_CONTAINERS+=("$container")
    elif docker exec "$container" sh -c "cat /etc/redhat-release 2>/dev/null | grep -qi 'fedora'" 2>/dev/null; then
        echo "Fedora (via redhat-release)"
        FEDORA_CONTAINERS+=("$container")
    else
        echo "Otra distribución"
        OTHER_CONTAINERS+=("$container")
    fi
done

# 3. Verificar estado de los contenedores
echo -e "\nVerificando estado de contenedores..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 4. Verificar instalación de herramientas (SOLO VERIFICACIÓN)
echo -e "\nVerificando herramientas y servicios..."

# Función para esperar que un contenedor esté listo
wait_for_container() {
    local container=$1
    local max_attempts=15
    local attempt=1
    
    echo -n "    Esperando que $container esté listo: "
    while [ $attempt -le $max_attempts ]; do
        if docker exec "$container" sh -c "echo 'ready'" >/dev/null 2>&1; then
            echo "OK (intento $attempt/$max_attempts)"
            return 0
        fi
        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done
    echo " TIMEOUT - Continuando de todos modos..."
    return 1
}

# Función para verificar Ubuntu (solo verificación)
check_ubuntu() {
    local container=$1
    echo "  $container (Ubuntu con Samba):"
    
    # Esperar a que el contenedor esté listo
    wait_for_container "$container"
    
    # Verificar herramientas
    echo -n "    Herramientas: "
    tools_missing=""
    for tool in nmap ip curl wget; do
        if ! timeout 5 docker exec "$container" bash -c "command -v $tool >/dev/null 2>&1" 2>/dev/null; then
            tools_missing="$tools_missing $tool"
        fi
    done
    
    if [ -z "$tools_missing" ]; then
        echo "Todas instaladas ✓"
    else
        echo "Faltan:$tools_missing"
    fi
    
    # Verificar servicios
    echo "    Servicios:"
    
    # Apache
    echo -n "      Apache: "
    if timeout 5 docker exec "$container" bash -c "ps aux | grep -E '[a]pache2|[h]ttpd'" >/dev/null 2>&1; then
        echo "Activo ✓"
    else
        echo "Inactivo"
    fi
    
    # SSH
    echo -n "      SSH: "
    if timeout 5 docker exec "$container" bash -c "ps aux | grep '[s]shd'" >/dev/null 2>&1; then
        echo "Activo ✓"
    else
        echo "Inactivo"
    fi
    
    # Samba
    echo -n "      Samba: "
    if timeout 5 docker exec "$container" bash -c "ps aux | grep '[s]mbd'" >/dev/null 2>&1; then
        echo "Activo ✓"
        # Verificar si está escuchando en puerto 445
        echo -n "      Puerto 445: "
        if timeout 5 docker exec "$container" bash -c "netstat -tlnp | grep ':445'" >/dev/null 2>&1; then
            echo "Escuchando ✓"
        else
            echo "No escuchando"
        fi
    elif timeout 5 docker exec "$container" bash -c "command -v smbd >/dev/null 2>&1" 2>/dev/null; then
        echo "Instalado pero inactivo"
    else
        echo "No instalado"
    fi
    
    # Verificar puertos internos
    echo "    Puertos internos:"
    if timeout 5 docker exec "$container" bash -c "netstat -tlnp 2>/dev/null | grep -E ':80|:22|:445'" >/dev/null 2>&1; then
        timeout 5 docker exec "$container" bash -c "netstat -tlnp 2>/dev/null | grep -E ':80|:22|:445'" | while read line; do
            echo "      $line"
        done
    else
        echo "      No se pudieron obtener puertos"
    fi
}

# Función para verificar Debian (solo verificación)
check_debian() {
    local container=$1
    echo "  $container (Debian):"
    
    # Esperar a que el contenedor esté listo
    wait_for_container "$container"
    
    # Verificar herramientas
    echo -n "    Herramientas: "
    tools_missing=""
    for tool in nmap ip curl wget; do
        if ! timeout 5 docker exec "$container" bash -c "command -v $tool >/dev/null 2>&1" 2>/dev/null; then
            tools_missing="$tools_missing $tool"
        fi
    done
    
    if [ -z "$tools_missing" ]; then
        echo "Todas instaladas ✓"
    else
        echo "Faltan:$tools_missing"
    fi
    
    # Verificar servicios
    echo "    Servicios:"
    
    # Apache
    echo -n "      Apache: "
    if timeout 5 docker exec "$container" bash -c "ps aux | grep -E '[a]pache2|[h]ttpd'" >/dev/null 2>&1; then
        echo "Activo ✓"
    else
        echo "Inactivo"
    fi
    
    # SSH
    echo -n "      SSH: "
    if timeout 5 docker exec "$container" bash -c "ps aux | grep '[s]shd'" >/dev/null 2>&1; then
        echo "Activo ✓"
    else
        echo "Inactivo"
    fi
    
    # Verificar puertos internos
    echo "    Puertos internos:"
    if timeout 5 docker exec "$container" bash -c "netstat -tlnp 2>/dev/null | grep -E ':80|:22'" >/dev/null 2>&1; then
        timeout 5 docker exec "$container" bash -c "netstat -tlnp 2>/dev/null | grep -E ':80|:22'" | while read line; do
            echo "      $line"
        done
    else
        echo "      No se pudieron obtener puertos"
    fi
}

# Función para verificar Fedora (solo verificación)
check_fedora() {
    local container=$1
    echo "  $container (Fedora - solo herramientas):"
    
    # Esperar a que el contenedor esté listo
    wait_for_container "$container"
    
    # Verificar herramientas
    echo -n "    Herramientas: "
    tools_missing=""
    for tool in nmap ip curl wget; do
        if ! timeout 5 docker exec "$container" bash -c "command -v $tool >/dev/null 2>&1" 2>/dev/null; then
            tools_missing="$tools_missing $tool"
        fi
    done
    
    if [ -z "$tools_missing" ]; then
        echo "Todas instaladas ✓"
    else
        echo "Faltan:$tools_missing"
    fi
    
    # Verificar que NO hay servicios web/ssh
    echo "    Servicios (deberían estar INACTIVOS):"
    
    # Apache
    echo -n "      Apache: "
    if timeout 5 docker exec "$container" bash -c "ps aux | grep -E '[a]pache2|[h]ttpd'" >/dev/null 2>&1; then
        echo "Activo (¡NO esperado!)"
    else
        echo "Inactivo ✓"
    fi
    
    # SSH
    echo -n "      SSH: "
    if timeout 5 docker exec "$container" bash -c "ps aux | grep '[s]shd'" >/dev/null 2>&1; then
        echo "Activo (¡NO esperado!)"
    else
        echo "Inactivo ✓"
    fi
    
    echo "    NOTA: Fedora está configurado solo con herramientas, sin servicios web"
}

# Verificar contenedores Ubuntu (con Samba)
if [ ${#UBUNTU_CONTAINERS[@]} -gt 0 ]; then
    echo -e "\nContenedores Ubuntu (con Samba):"
    for container in "${UBUNTU_CONTAINERS[@]}"; do
        check_ubuntu "$container"
    done
fi

# Verificar contenedores Debian
if [ ${#DEBIAN_CONTAINERS[@]} -gt 0 ]; then
    echo -e "\nContenedores Debian:"
    for container in "${DEBIAN_CONTAINERS[@]}"; do
        check_debian "$container"
    done
fi

# Verificar contenedores Fedora
if [ ${#FEDORA_CONTAINERS[@]} -gt 0 ]; then
    echo -e "\nContenedores Fedora:"
    for container in "${FEDORA_CONTAINERS[@]}"; do
        check_fedora "$container"
    done
fi

# Verificar otros contenedores
if [ ${#OTHER_CONTAINERS[@]} -gt 0 ]; then
    echo -e "\nOtros contenedores:"
    for container in "${OTHER_CONTAINERS[@]}"; do
        echo "  $container: Distribución no identificada - verificando básico..."
        if wait_for_container "$container"; then
            echo "    Contenedor accesible"
        else
            echo "    Contenedor no accesible"
        fi
    done
fi

# 5. Obtener IPs y configurar /etc/hosts
echo -e "\nObteniendo IPs de contenedores..."

declare -A CONTAINER_IPS
for container in "${CONTAINERS[@]}"; do
    # Método 1: Usar docker inspect
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container" 2>/dev/null)
    
    # Método 2: Alternativo si el anterior falla
    if [ -z "$ip" ] || [ "$ip" = "<no value>" ]; then
        ip=$(docker exec "$container" sh -c "ip route get 1 | awk '{print \$NF;exit}' 2>/dev/null" 2>/dev/null)
    fi
    
    # Método 3: Otra alternativa
    if [ -z "$ip" ] || [ "$ip" = "<no value>" ]; then
        ip=$(docker exec "$container" sh -c "hostname -I | awk '{print \$1}' 2>/dev/null" 2>/dev/null)
    fi
    
    if [ -n "$ip" ] && [ "$ip" != "<no value>" ]; then
        CONTAINER_IPS["$container"]=$ip
        echo "  $container: $ip"
    else
        echo "  $container: No se pudo obtener IP"
        CONTAINER_IPS["$container"]=""
    fi
done

# 6. Configurar archivos /etc/hosts para resolución por nombre
echo -e "\nConfigurando resolución por nombre en /etc/hosts..."

configure_hosts() {
    local container=$1
    shift
    local containers=("$@")
    
    # Crear archivo temporal con todas las entradas
    local temp_hosts=""
    for target_container in "${containers[@]}"; do
        if [ "$target_container" != "$container" ] && [ -n "${CONTAINER_IPS[$target_container]}" ]; then
            temp_hosts="${temp_hosts}${CONTAINER_IPS[$target_container]} $target_container\n"
        fi
    done
    
    # Añadir al /etc/hosts del contenedor
    if [ -n "$temp_hosts" ]; then
        if docker exec "$container" sh -c "
            # Limpiar entradas antiguas
            sed -i '/# Added by container setup/d' /etc/hosts 2>/dev/null
            
            # Añadir nuevas entradas
            echo '# Added by container setup' >> /etc/hosts
            echo -e '$temp_hosts' >> /etc/hosts
        " 2>/dev/null; then
            entries=$(echo -e "$temp_hosts" | grep -c .)
            echo "  $container: Configurado con $entries entradas ✓"
        else
            echo "  $container: Error al configurar /etc/hosts"
        fi
    else
        echo "  $container: No hay IPs para configurar"
    fi
}

for container in "${CONTAINERS[@]}"; do
    configure_hosts "$container" "${CONTAINERS[@]}"
done

# 7. Pruebas de conectividad básica
echo -e "\nRealizando pruebas básicas de conectividad..."

echo "1. Probando ping entre contenedores (2 intentos por conexión):"
for i in "${!CONTAINERS[@]}"; do
    for j in "${!CONTAINERS[@]}"; do
        if [ $i -ne $j ] && [ -n "${CONTAINER_IPS[${CONTAINERS[$j]}]}" ]; then
            src="${CONTAINERS[$i]}"
            dst="${CONTAINERS[$j]}"
            dst_ip="${CONTAINER_IPS[$dst]}"
            
            echo -n "  $src → $dst ($dst_ip): "
            if docker exec "$src" timeout 5 ping -c 2 "$dst_ip" >/dev/null 2>&1; then
                echo "OK ✓"
            else
                echo "Falló ✗"
            fi
        fi
    done
done

echo -e "\n2. Probando resolución por nombre:"
for container in "${CONTAINERS[@]}"; do
    echo -n "  $container puede resolver: "
    resolved=0
    for target in "${CONTAINERS[@]}"; do
        if [ "$container" != "$target" ]; then
            if docker exec "$container" timeout 3 getent hosts "$target" >/dev/null 2>&1; then
                resolved=$((resolved + 1))
            fi
        fi
    done
    echo "$resolved de $((${#CONTAINERS[@]} - 1)) nombres ✓"
done

# 8. Mostrar configuración de puertos expuestos
echo -e "\nConfiguración de puertos expuestos al host:"
for container in "${CONTAINERS[@]}"; do
    ports=$(docker port "$container" 2>/dev/null || echo "No expone puertos")
    echo "  $container:"
    echo "$ports" | sed 's/^/    /'
done

# 9. Resumen final
echo -e "\n=== RESÚMEN FINAL ==="
echo "Total contenedores configurados: ${#CONTAINERS[@]}"

if [ ${#UBUNTU_CONTAINERS[@]} -gt 0 ]; then
    echo -e "\nContenedores Ubuntu (con Samba):"
    for container in "${UBUNTU_CONTAINERS[@]}"; do
        ip=${CONTAINER_IPS[$container]:-"IP no disponible"}
        echo "  - $container"
        echo "    IP: $ip"
        echo "    Puertos host: 8080→80, 2222→22, 445→445"
        echo "    Servicios: Apache, SSH, Samba"
        echo "    Acceso web: http://localhost:8080"
        echo "    Acceso SSH: ssh root@localhost -p 2222 (password: password)"
        echo "    Acceso SMB: smb://localhost/"
    done
fi

if [ ${#DEBIAN_CONTAINERS[@]} -gt 0 ]; then
    echo -e "\nContenedores Debian:"
    for container in "${DEBIAN_CONTAINERS[@]}"; do
        ip=${CONTAINER_IPS[$container]:-"IP no disponible"}
        echo "  - $container"
        echo "    IP: $ip"
        echo "    Puertos host: 8081→80, 2223→22"
        echo "    Servicios: Apache, SSH"
        echo "    Acceso web: http://localhost:8081"
        echo "    Acceso SSH: ssh root@localhost -p 2223 (password: password)"
    done
fi

if [ ${#FEDORA_CONTAINERS[@]} -gt 0 ]; then
    echo -e "\nContenedores Fedora:"
    for container in "${FEDORA_CONTAINERS[@]}"; do
        ip=${CONTAINER_IPS[$container]:-"IP no disponible"}
        echo "  - $container"
        echo "    IP: $ip"
        echo "    Puertos host: No expone puertos"
        echo "    Configuración: Solo herramientas (nmap, net-tools, etc.)"
        echo "    Uso: docker exec -it $container bash"
    done
fi

# 10. Comandos útiles
echo -e "\n=== COMANDOS ÚTILES ==="
echo "Acceder a contenedores:"
for container in "${CONTAINERS[@]}"; do
    echo "  docker exec -it $container bash"
done

echo -e "\nPruebas de seguridad/red recomendadas:"
echo "1. Escaneo de red desde Ubuntu:"
echo "   docker exec tfm_ubuntu nmap -sP 172.30.0.0/24"
echo "   docker exec tfm_ubuntu nmap -sV 172.30.0.0/24"
echo ""
echo "2. Pruebas SMB desde Ubuntu:"
echo "   docker exec tfm_ubuntu nmap --script smb-os-discovery -p 445 172.30.0.0/24"
echo "   docker exec tfm_ubuntu smbclient -L //tfm_ubuntu/ -U guest"
echo ""
echo "3. Pruebas SSH desde Debian:"
echo "   docker exec tfm_debian nmap --script ssh-auth-methods -p 22 172.30.0.0/24"
echo ""
echo "4. Ver logs de servicios:"
echo "   docker logs tfm_ubuntu"
echo "   docker logs tfm_debian"

echo -e "\nPara reiniciar servicios (si es necesario):"
echo "  docker exec tfm_ubuntu service apache2 restart"
echo "  docker exec tfm_ubuntu service smbd restart"
echo "  docker exec tfm_ubuntu service ssh restart"

echo -e "\nPara detener todos los contenedores:"
echo "  docker compose down"

echo -e "\nPara ver el estado actual:"
echo "  docker ps"

echo -e "\n¡Configuración completada! ✓"