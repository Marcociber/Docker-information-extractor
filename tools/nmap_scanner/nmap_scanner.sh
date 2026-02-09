#!/bin/bash
# nmap_vuln_scanner.sh - Escaneo con scripts de vulnerabilidad

# ========================================================
# VERIFICACIÓN DE USUARIO ROOT
# ========================================================
if [ "$EUID" -ne 0 ]; then 
    echo "========================================================"
    echo "  ERROR: PERMISOS INSUFICIENTES"
    echo "========================================================"
    echo "  Este script debe ejecutarse como usuario root"
    echo ""
    echo "  Por favor, ejecute con:"
    echo "    sudo ./$(basename "$0")"
    echo ""
    echo "  O alternativamente:"
    echo "    su -c './$(basename "$0")'"
    echo "========================================================"
    exit 1
fi

SCANS_DIR="nmap_scans"
mkdir -p "$SCANS_DIR"

echo "========================================================"
echo "ESCANEO NMAP DE VULNERABILIDADES PARA CONTENEDORES DOCKER"
echo "========================================================"
echo "COMANDO: nmap -A -T4 -p- -sV -sC --script vuln"
echo "========================================================"

# Verificar Docker
if ! docker ps &>/dev/null; then
    echo "Error: Docker no está corriendo o sin permisos"
    exit 1
fi

# Verificar nmap
if ! command -v nmap &>/dev/null; then
    echo "Nmap no encontrado. Instalando..."
    apt update && apt install -y nmap
fi

# Verificar scripts de nmap
echo "Verificando scripts NSE..."
if [ ! -d "/usr/share/nmap/scripts/" ]; then
    echo "Instalando scripts NSE..."
    apt install -y nmap-scripts
fi

# Obtener contenedores corriendo
CONTAINERS=$(docker ps --format "{{.Names}}")

if [ -z "$CONTAINERS" ]; then
    echo "No hay contenedores corriendo"
    exit 1
fi

echo ""
echo "Contenedores encontrados:"
for CONTAINER in $CONTAINERS; do
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)
    IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER" 2>/dev/null)
    echo "  - $CONTAINER: $IP ($IMAGE)"
done
echo ""

# Archivos de salida
JSON_FILE="$SCANS_DIR/nmap_results.json"
TXT_FILE="$SCANS_DIR/nmap_results.txt"

# Crear JSON
echo "{" > "$JSON_FILE"
echo '  "scan_type": "vulnerability_assessment",' >> "$JSON_FILE"
echo '  "command": "nmap -A -T4 -p- -sV -sC --script vuln",' >> "$JSON_FILE"
echo '  "timestamp": "'$(date -Iseconds)'",' >> "$JSON_FILE"
echo '  "host": "'$(hostname)'",' >> "$JSON_FILE"
echo '  "docker_version": "'$(docker --version 2>/dev/null | cut -d, -f1)'",' >> "$JSON_FILE"
echo '  "nmap_version": "'$(nmap --version 2>/dev/null | head -n1)'",' >> "$JSON_FILE"
echo '  "scans": {' >> "$JSON_FILE"

# Crear TXT
echo "========================================================" > "$TXT_FILE"
echo "ESCANEO DE VULNERABILIDADES NMAP" >> "$TXT_FILE"
echo "========================================================" >> "$TXT_FILE"
echo "" >> "$TXT_FILE"
echo "FECHA: $(date '+%Y-%m-%d %H:%M:%S')" >> "$TXT_FILE"
echo "HOST: $(hostname)" >> "$TXT_FILE"
echo "COMANDO: nmap -A -T4 -p- -sV -sC --script vuln" >> "$TXT_FILE"
echo "DOCKER: $(docker --version 2>/dev/null | cut -d, -f1)" >> "$TXT_FILE"
echo "NMAP: $(nmap --version 2>/dev/null | head -n1)" >> "$TXT_FILE"
echo "" >> "$TXT_FILE"
echo "========================================================" >> "$TXT_FILE"
echo "RESUMEN EJECUTIVO" >> "$TXT_FILE"
echo "========================================================" >> "$TXT_FILE"
echo "" >> "$TXT_FILE"

# Variables para estadísticas
FIRST=true
TOTAL_CONTAINERS=0
SUCCESS_SCANS=0
TOTAL_VULNS=0
TOTAL_OPEN_PORTS=0

# Procesar cada contenedor
for CONTAINER in $CONTAINERS; do
    TOTAL_CONTAINERS=$((TOTAL_CONTAINERS + 1))
    
    # Obtener información del contenedor
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)
    
    if [ -z "$IP" ] || [ "$IP" = "<no value>" ]; then
        echo "  $CONTAINER: Sin IP válida, saltando..."
        echo "" >> "$TXT_FILE"
        echo "CONTENEDOR: $CONTAINER" >> "$TXT_FILE"
        echo "ERROR: Sin IP válida" >> "$TXT_FILE"
        echo "----------------------------------------" >> "$TXT_FILE"
        continue
    fi
    
    IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER" 2>/dev/null)
    CREATED=$(docker inspect -f '{{.Created}}' "$CONTAINER" 2>/dev/null | cut -d'T' -f1)
    
    echo ""
    echo "========================================================"
    echo "ESCANEANDO: $CONTAINER"
    echo "IP: $IP"
    echo "Imagen: $IMAGE"
    echo "========================================================"
    
    # Separador JSON
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$JSON_FILE"
    fi
    
    # Guardar en TXT
    echo "" >> "$TXT_FILE"
    echo "========================================================" >> "$TXT_FILE"
    echo "CONTENEDOR: $CONTAINER" >> "$TXT_FILE"
    echo "========================================================" >> "$TXT_FILE"
    echo "IP: $IP" >> "$TXT_FILE"
    echo "Imagen Docker: $IMAGE" >> "$TXT_FILE"
    echo "Creado: $CREATED" >> "$TXT_FILE"
    echo "" >> "$TXT_FILE"
    echo "--- INICIO ESCANEO $(date '+%H:%M:%S') ---" >> "$TXT_FILE"
    echo "" >> "$TXT_FILE"
    
    # Escaneo con scripts de vulnerabilidad
    echo "Ejecutando escaneo completo de vulnerabilidades..."
    echo "Esto puede tardar 15-20 minutos por contenedor..."
    
    START_TIME=$(date +%s)
    
    # Ejecutar nmap con timeout extendido (20 minutos)
    NMAP_OUTPUT=$(timeout 1200 nmap -A -T4 -p- -sV -sC --script vuln "$IP" 2>&1)
    RETURN_CODE=$?
    
    END_TIME=$(date +%s)
    SCAN_TIME=$((END_TIME - START_TIME))
    MINUTES=$((SCAN_TIME / 60))
    SECONDS=$((SCAN_TIME % 60))
    
    # Análisis de resultados
    HOST_STATUS=$(echo "$NMAP_OUTPUT" | grep -E "Host is up|Host seems down" | head -1)
    OPEN_PORTS=$(echo "$NMAP_OUTPUT" | grep -E "^[0-9]+/tcp.*open" | wc -l)
    VULNERABILITIES=$(echo "$NMAP_OUTPUT" | grep -E "VULNERABLE:|State: VULNERABLE" | wc -l)
    SERVICE_INFO=$(echo "$NMAP_OUTPUT" | grep "Service Info:" | head -1)
    OS_INFO=$(echo "$NMAP_OUTPUT" | grep -E "OS details:|Running:|OS:" | head -1)
    
    TOTAL_OPEN_PORTS=$((TOTAL_OPEN_PORTS + OPEN_PORTS))
    TOTAL_VULNS=$((TOTAL_VULNS + VULNERABILITIES))
    
    if [ $RETURN_CODE -eq 0 ]; then
        SUCCESS_SCANS=$((SUCCESS_SCANS + 1))
        STATUS="COMPLETADO"
        echo "Escaneo completado en ${MINUTES}m ${SECONDS}s"
    elif [ $RETURN_CODE -eq 124 ]; then
        STATUS="TIMEOUT"
        echo "Timeout después de 20 minutos"
    else
        STATUS="ERROR"
        echo "Error en escaneo (código: $RETURN_CODE)"
    fi
    
    # Mostrar resumen
    echo "  Puertos abiertos: $OPEN_PORTS"
    echo "  Vulnerabilidades: $VULNERABILITIES"
    if [ ! -z "$SERVICE_INFO" ]; then
        echo "  Servicios: $(echo $SERVICE_INFO | cut -d: -f2- | cut -c1-50)..."
    fi
    
    # Guardar en JSON
    echo '    "'$CONTAINER'": {' >> "$JSON_FILE"
    echo '      "container_name": "'$CONTAINER'",' >> "$JSON_FILE"
    echo '      "ip": "'$IP'",' >> "$JSON_FILE"
    echo '      "image": "'$IMAGE'",' >> "$JSON_FILE"
    echo '      "scan_status": "'$STATUS'",' >> "$JSON_FILE"
    echo '      "scan_time_seconds": '$SCAN_TIME',' >> "$JSON_FILE"
    echo '      "scan_time_human": "'${MINUTES}m ${SECONDS}s'",' >> "$JSON_FILE"
    echo '      "return_code": '$RETURN_CODE',' >> "$JSON_FILE"
    echo '      "host_status": "'$(echo $HOST_STATUS | sed 's/"/\\"/g')'",' >> "$JSON_FILE"
    echo '      "open_ports_count": '$OPEN_PORTS',' >> "$JSON_FILE"
    echo '      "vulnerabilities_count": '$VULNERABILITIES',' >> "$JSON_FILE"
    echo '      "service_info": "'$(echo $SERVICE_INFO | sed 's/"/\\"/g')'",' >> "$JSON_FILE"
    echo '      "os_info": "'$(echo $OS_INFO | sed 's/"/\\"/g')'",' >> "$JSON_FILE"
    
    # Lista de puertos abiertos
    echo '      "open_ports": [' >> "$JSON_FILE"
    PORT_LIST=$(echo "$NMAP_OUTPUT" | grep -E "^[0-9]+/tcp.*open")
    if [ ! -z "$PORT_LIST" ]; then
        PORT_INDEX=0
        echo "$PORT_LIST" | while read -r PORT_LINE; do
            PORT_INDEX=$((PORT_INDEX + 1))
            PORT=$(echo "$PORT_LINE" | awk '{print $1}')
            STATE=$(echo "$PORT_LINE" | awk '{print $2}')
            SERVICE=$(echo "$PORT_LINE" | awk '{print $3}')
            VERSION=$(echo "$PORT_LINE" | cut -d' ' -f4-)
            
            echo '        {' >> "$JSON_FILE"
            echo '          "port": "'$PORT'",' >> "$JSON_FILE"
            echo '          "state": "'$STATE'",' >> "$JSON_FILE"
            echo '          "service": "'$SERVICE'",' >> "$JSON_FILE"
            echo '          "version": "'$(echo $VERSION | sed 's/"/\\"/g')'"' >> "$JSON_FILE"
            if [ $PORT_INDEX -lt $(echo "$PORT_LIST" | wc -l) ]; then
                echo '        },' >> "$JSON_FILE"
            else
                echo '        }' >> "$JSON_FILE"
            fi
        done
    fi
    echo '      ],' >> "$JSON_FILE"
    
    # Lista de vulnerabilidades encontradas
    echo '      "vulnerabilities": [' >> "$JSON_FILE"
    VULN_LIST=$(echo "$NMAP_OUTPUT" | grep -E "VULNERABLE:|State: VULNERABLE" | head -10)
    if [ ! -z "$VULN_LIST" ]; then
        VULN_INDEX=0
        echo "$VULN_LIST" | while read -r VULN_LINE; do
            VULN_INDEX=$((VULN_INDEX + 1))
            VULN_CLEAN=$(echo "$VULN_LINE" | sed 's/"/\\"/g')
            echo '        "'$VULN_CLEAN'"' >> "$JSON_FILE"
            if [ $VULN_INDEX -lt $(echo "$VULN_LIST" | wc -l) ]; then
                echo '        ,' >> "$JSON_FILE"
            fi
        done
    fi
    echo '      ]' >> "$JSON_FILE"
    
    echo '    }' >> "$JSON_FILE"
    
    # Guardar salida completa en TXT
    echo "ESTADO: $STATUS" >> "$TXT_FILE"
    echo "TIEMPO: ${MINUTES}m ${SECONDS}s" >> "$TXT_FILE"
    echo "CODIGO SALIDA: $RETURN_CODE" >> "$TXT_FILE"
    echo "" >> "$TXT_FILE"
    
    echo "RESULTADOS:" >> "$TXT_FILE"
    echo "-----------" >> "$TXT_FILE"
    
    if [ ! -z "$HOST_STATUS" ]; then
        echo "Host: $HOST_STATUS" >> "$TXT_FILE"
    fi
    
    echo "Puertos abiertos: $OPEN_PORTS" >> "$TXT_FILE"
    echo "Vulnerabilidades encontradas: $VULNERABILITIES" >> "$TXT_FILE"
    echo "" >> "$TXT_FILE"
    
    if [ $OPEN_PORTS -gt 0 ]; then
        echo "PUERTOS ABIERTOS:" >> "$TXT_FILE"
        echo "$PORT_LIST" >> "$TXT_FILE"
        echo "" >> "$TXT_FILE"
    fi
    
    if [ ! -z "$SERVICE_INFO" ]; then
        echo "INFORMACION DE SERVICIOS:" >> "$TXT_FILE"
        echo "$SERVICE_INFO" >> "$TXT_FILE"
        echo "" >> "$TXT_FILE"
    fi
    
    if [ ! -z "$OS_INFO" ]; then
        echo "DETECCION DE SISTEMA OPERATIVO:" >> "$TXT_FILE"
        echo "$OS_INFO" >> "$TXT_FILE"
        echo "" >> "$TXT_FILE"
    fi
    
    if [ $VULNERABILITIES -gt 0 ]; then
        echo "VULNERABILIDADES ENCONTRADAS ($VULNERABILITIES):" >> "$TXT_FILE"
        echo "$VULN_LIST" >> "$TXT_FILE"
        echo "" >> "$TXT_FILE"
    fi
    
    # Si hay pocos resultados, mostrar output completo
    if [ $(echo "$NMAP_OUTPUT" | wc -l) -lt 100 ]; then
        echo "SALIDA COMPLETA NMAP:" >> "$TXT_FILE"
        echo "---------------------" >> "$TXT_FILE"
        echo "$NMAP_OUTPUT" >> "$TXT_FILE"
    else
        echo "ULTIMAS 20 LINEAS DE SALIDA:" >> "$TXT_FILE"
        echo "---------------------------" >> "$TXT_FILE"
        echo "$NMAP_OUTPUT" | tail -20 >> "$TXT_FILE"
    fi
    
    echo "" >> "$TXT_FILE"
    echo "--- FIN ESCANEO $(date '+%H:%M:%S') ---" >> "$TXT_FILE"
    echo "" >> "$TXT_FILE"
    echo "========================================================" >> "$TXT_FILE"
    
    # Pequeña pausa entre escaneos
    if [ $TOTAL_CONTAINERS -lt $(echo "$CONTAINERS" | wc -w) ]; then
        echo "Esperando 10 segundos antes del proximo escaneo..."
        sleep 10
    fi
done

# Cerrar JSON
echo '  }' >> "$JSON_FILE"
echo '}' >> "$JSON_FILE"

# Finalizar TXT con estadísticas
echo "" >> "$TXT_FILE"
echo "========================================================" >> "$TXT_FILE"
echo "ESTADISTICAS GLOBALES" >> "$TXT_FILE"
echo "========================================================" >> "$TXT_FILE"
echo "" >> "$TXT_FILE"
echo "Contenedores totales: $TOTAL_CONTAINERS" >> "$TXT_FILE"
echo "Escaneos exitosos: $SUCCESS_SCANS" >> "$TXT_FILE"
echo "Puertos abiertos totales: $TOTAL_OPEN_PORTS" >> "$TXT_FILE"
echo "Vulnerabilidades encontradas: $TOTAL_VULNS" >> "$TXT_FILE"
echo "" >> "$TXT_FILE"

if [ $TOTAL_VULNS -gt 0 ]; then
    echo "  ADVERTENCIA: Se encontraron $TOTAL_VULNS vulnerabilidades" >> "$TXT_FILE"
    echo "   Revise los resultados detallados por contenedor." >> "$TXT_FILE"
else
    echo " No se encontraron vulnerabilidades en los escaneos." >> "$TXT_FILE"
fi

echo "" >> "$TXT_FILE"
echo "Reporte generado: $(date '+%Y-%m-%d %H:%M:%S')" >> "$TXT_FILE"
echo "Duracion total: ~$((TOTAL_CONTAINERS * 15)) minutos estimados" >> "$TXT_FILE"
echo "Archivos guardados en: $SCANS_DIR/" >> "$TXT_FILE"
echo "========================================================" >> "$TXT_FILE"

echo ""
echo "========================================================"
echo "ESCANEOS COMPLETADOS"
echo "========================================================"
echo "Estadisticas:"
echo "  • Contenedores escaneados: $SUCCESS_SCANS/$TOTAL_CONTAINERS"
echo "  • Puertos abiertos encontrados: $TOTAL_OPEN_PORTS"
echo "  • Vulnerabilidades detectadas: $TOTAL_VULNS"
echo ""
echo "Resultados guardados en:"
echo "  $JSON_FILE"
echo "  $TXT_FILE"
echo ""
echo "Para ver vulnerabilidades:"
echo "  grep -i 'vulnerable' $TXT_FILE"
echo "========================================================"
