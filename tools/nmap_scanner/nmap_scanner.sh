#!/bin/bash
# nmap_vuln_scanner.sh - Escaneo con scripts de vulnerabilidad
# Versión: 2.1 - Con gestión automática de carpetas y limpieza
#              - Asegura directorio único por ejecución (incluso mismo segundo)

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

# ========================================================
# CONFIGURACIÓN DE DIRECTORIOS
# ========================================================
# Crear carpeta principal de escaneos
BASE_SCANS_DIR="nmap_scans"
mkdir -p "$BASE_SCANS_DIR"

# ------------------------------------------------------------------
# GENERAR NOMBRE DE DIRECTORIO ÚNICO (incluso en el mismo segundo)
# ------------------------------------------------------------------
CURRENT_DATE=$(date '+%Y%m%d_%H%M%S')
BASE_SCAN_NAME="nmap_scan_${CURRENT_DATE}"
SCANS_DIR="${BASE_SCANS_DIR}/${BASE_SCAN_NAME}"

# Si el directorio ya existe, añadir sufijo _1, _2, ...
COUNTER=1
while [ -d "$SCANS_DIR" ]; do
    SCANS_DIR="${BASE_SCANS_DIR}/${BASE_SCAN_NAME}_${COUNTER}"
    COUNTER=$((COUNTER + 1))
done

# Crear estructura de carpetas
mkdir -p "$SCANS_DIR/logs"
mkdir -p "$SCANS_DIR/results"
mkdir -p "$SCANS_DIR/raw"

echo "========================================================"
echo "ESCANEO NMAP DE VULNERABILIDADES PARA CONTENEDORES DOCKER"
echo "========================================================"
echo "COMANDO: nmap -A -T4 -p- -sV -sC --script vuln"
echo "DIRECTORIO: $SCANS_DIR"
echo "========================================================"

# ========================================================
# FUNCIÓN DE LIMPIEZA AUTOMÁTICA (48 HORAS)
# ========================================================
setup_auto_cleanup() {
    local scan_dir="$1"
    local folder_name=$(basename "$scan_dir")
    # Nombre único para el script de limpieza basado en el directorio final
    local cleanup_script="/tmp/cleanup_${folder_name}.sh"
    
    # Crear script de limpieza
    cat > "$cleanup_script" << EOF
#!/bin/bash
# Script de limpieza automática - Se ejecutará en 48 horas
SCAN_DIR="$scan_dir"
DELETE_TIME=\$(date -d "48 hours ago" +%s)
DIR_TIME=\$(stat -c %Y "\$SCAN_DIR" 2>/dev/null)

if [ -d "\$SCAN_DIR" ] && [ "\$DIR_TIME" -lt "\$DELETE_TIME" ]; then
    echo "[AUTO-CLEANUP] Eliminando carpeta antigua: \$SCAN_DIR"
    rm -rf "\$SCAN_DIR"
    echo "[AUTO-CLEANUP] Carpeta eliminada: \$(basename \$SCAN_DIR)"
fi

# Auto-eliminar este script después de ejecutar
rm -f "$cleanup_script"
EOF
    
    chmod +x "$cleanup_script"
    
    # Programar limpieza con at (48 horas)
    if command -v at &>/dev/null; then
        echo "bash $cleanup_script" | at now + 48 hours 2>/dev/null
        echo "[INFO] Limpieza programada para 48 horas después"
    # Alternativa con cron si at no está disponible
    elif command -v crontab &>/dev/null; then
        CRON_JOB="@reboot sleep 172800 && bash $cleanup_script"
        (crontab -l 2>/dev/null | grep -v "$cleanup_script"; echo "$CRON_JOB") | crontab -
        echo "[INFO] Limpieza programada vía cron para 48 horas después"
    else
        echo "[ADVERTENCIA] No se pudo programar limpieza automática"
        echo "              Elimine manualmente en 48 horas:"
        echo "              rm -rf $scan_dir"
    fi
}

# Configurar limpieza automática
setup_auto_cleanup "$SCANS_DIR"

# ========================================================
# VERIFICACIONES DEL SISTEMA
# ========================================================
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

# ========================================================
# ARCHIVOS DE REGISTRO Y RESULTADOS
# ========================================================
# Archivos de salida
JSON_FILE="$SCANS_DIR/results/nmap_results.json"
TXT_FILE="$SCANS_DIR/results/nmap_results.txt"
LOG_FILE="$SCANS_DIR/logs/scan_execution.log"
SUMMARY_FILE="$SCANS_DIR/results/executive_summary.txt"

# Iniciar archivo de log
{
echo "========================================================"
echo "LOG DE EJECUCIÓN - NMAP VULNERABILITY SCAN"
echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Directorio: $SCANS_DIR"
echo "Hostname: $(hostname)"
echo "Usuario: $(whoami)"
echo "========================================================"
} > "$LOG_FILE"

# ========================================================
# DETECCIÓN DE CONTENEDORES
# ========================================================
echo ""
echo "Buscando contenedores Docker..."
echo "Buscando contenedores Docker..." >> "$LOG_FILE"

# Obtener contenedores corriendo
CONTAINERS=$(docker ps --format "{{.Names}}")

if [ -z "$CONTAINERS" ]; then
    echo "No hay contenedores corriendo" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Contenedores encontrados: $CONTAINERS" >> "$LOG_FILE"

echo ""
echo "Contenedores encontrados:"
{
echo "========================================================"
echo "CONTENEDORES DETECTADOS"
echo "========================================================"
} > "$SUMMARY_FILE"

for CONTAINER in $CONTAINERS; do
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)
    IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER" 2>/dev/null)
    echo "  - $CONTAINER: $IP ($IMAGE)"
    echo "  - $CONTAINER: $IP ($IMAGE)" >> "$SUMMARY_FILE"
done

echo "" >> "$SUMMARY_FILE"

# ========================================================
# PREPARAR ARCHIVOS DE RESULTADOS
# ========================================================
# Crear JSON
echo "{" > "$JSON_FILE"
echo '  "scan_type": "vulnerability_assessment",' >> "$JSON_FILE"
echo '  "command": "nmap -A -T4 -p- -sV -sC --script vuln",' >> "$JSON_FILE"
echo '  "timestamp": "'$(date -Iseconds)'",' >> "$JSON_FILE"
echo '  "scan_directory": "'$SCANS_DIR'",' >> "$JSON_FILE"
echo '  "host": "'$(hostname)'",' >> "$JSON_FILE"
echo '  "docker_version": "'$(docker --version 2>/dev/null | cut -d, -f1)'",' >> "$JSON_FILE"
echo '  "nmap_version": "'$(nmap --version 2>/dev/null | head -n1)'",' >> "$JSON_FILE"
echo '  "scans": {' >> "$JSON_FILE"

# Crear TXT
{
echo "========================================================"
echo "ESCANEO DE VULNERABILIDADES NMAP"
echo "========================================================"
echo ""
echo "FECHA: $(date '+%Y-%m-%d %H:%M:%S')"
echo "DIRECTORIO: $SCANS_DIR"
echo "HOST: $(hostname)"
echo "COMANDO: nmap -A -T4 -p- -sV -sC --script vuln"
echo "DOCKER: $(docker --version 2>/dev/null | cut -d, -f1)"
echo "NMAP: $(nmap --version 2>/dev/null | head -n1)"
echo ""
echo "========================================================"
echo "RESUMEN EJECUTIVO"
echo "========================================================"
echo ""
} > "$TXT_FILE"

# Variables para estadísticas
FIRST=true
TOTAL_CONTAINERS=0
SUCCESS_SCANS=0
TOTAL_VULNS=0
TOTAL_OPEN_PORTS=0

# ========================================================
# ESCANEO DE CONTENEDORES
# ========================================================
echo "" >> "$LOG_FILE"
echo "INICIANDO ESCANEOS INDIVIDUALES" >> "$LOG_FILE"
echo "========================================================" >> "$LOG_FILE"

# Procesar cada contenedor
for CONTAINER in $CONTAINERS; do
    TOTAL_CONTAINERS=$((TOTAL_CONTAINERS + 1))
    
    # Obtener información del contenedor
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)
    
    if [ -z "$IP" ] || [ "$IP" = "<no value>" ]; then
        echo "  $CONTAINER: Sin IP válida, saltando..."
        echo "[$(date '+%H:%M:%S')] $CONTAINER: Sin IP válida, saltando..." >> "$LOG_FILE"
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
    
    echo "[$(date '+%H:%M:%S')] Iniciando escaneo: $CONTAINER ($IP)" >> "$LOG_FILE"
    
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
    
    # Archivo para salida cruda
    RAW_OUTPUT_FILE="$SCANS_DIR/raw/${CONTAINER}_scan_$(date '+%H%M%S').txt"
    
    # Ejecutar nmap con timeout extendido (20 minutos)
    echo "[$(date '+%H:%M:%S')] Ejecutando nmap en $IP..." >> "$LOG_FILE"
    NMAP_OUTPUT=$(timeout 1200 nmap -A -T4 -p- -sV -sC --script vuln "$IP" 2>&1)
    RETURN_CODE=$?
    
    # Guardar salida cruda
    echo "$NMAP_OUTPUT" > "$RAW_OUTPUT_FILE"
    echo "[$(date '+%H:%M:%S')] Salida cruda guardada en: $(basename $RAW_OUTPUT_FILE)" >> "$LOG_FILE"
    
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
        echo "[$(date '+%H:%M:%S')] $CONTAINER: Escaneo completado (${MINUTES}m ${SECONDS}s)" >> "$LOG_FILE"
    elif [ $RETURN_CODE -eq 124 ]; then
        STATUS="TIMEOUT"
        echo "Timeout después de 20 minutos"
        echo "[$(date '+%H:%M:%S')] $CONTAINER: Timeout después de 20 minutos" >> "$LOG_FILE"
    else
        STATUS="ERROR"
        echo "Error en escaneo (código: $RETURN_CODE)"
        echo "[$(date '+%H:%M:%S')] $CONTAINER: Error (código: $RETURN_CODE)" >> "$LOG_FILE"
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
    echo '      "raw_output_file": "'$(basename $RAW_OUTPUT_FILE)'",' >> "$JSON_FILE"
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
    echo "ARCHIVO CRUDO: $(basename $RAW_OUTPUT_FILE)" >> "$TXT_FILE"
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
        echo "[$(date '+%H:%M:%S')] Pausa de 10 segundos..." >> "$LOG_FILE"
        sleep 10
    fi
done

# ========================================================
# FINALIZACIÓN Y ESTADÍSTICAS
# ========================================================
# Cerrar JSON
echo '  }' >> "$JSON_FILE"
echo '}' >> "$JSON_FILE"

# Finalizar TXT con estadísticas
{
echo ""
echo "========================================================"
echo "ESTADISTICAS GLOBALES"
echo "========================================================"
echo ""
echo "Contenedores totales: $TOTAL_CONTAINERS"
echo "Escaneos exitosos: $SUCCESS_SCANS"
echo "Puertos abiertos totales: $TOTAL_OPEN_PORTS"
echo "Vulnerabilidades encontradas: $TOTAL_VULNS"
echo ""
} >> "$TXT_FILE"

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

# Crear archivo de metadatos
METADATA_FILE="$SCANS_DIR/scan_metadata.txt"
{
echo "========================================================"
echo "METADATOS DEL ESCANEO"
echo "========================================================"
echo "Fecha creación: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Directorio: $SCANS_DIR"
echo "Fecha expiración: $(date -d "48 hours" '+%Y-%m-%d %H:%M:%S')"
echo "Estado: COMPLETADO"
echo "Contenedores escaneados: $SUCCESS_SCANS/$TOTAL_CONTAINERS"
echo "Vulnerabilidades encontradas: $TOTAL_VULNS"
echo "========================================================"
echo ""
echo "ESTRUCTURA DEL DIRECTORIO:"
echo "├── logs/               - Archivos de registro de ejecución"
echo "│   └── scan_execution.log"
echo "├── results/            - Resultados procesados"
echo "│   ├── nmap_results.json"
echo "│   ├── nmap_results.txt"
echo "│   └── executive_summary.txt"
echo "├── raw/               - Salidas crudas de nmap por contenedor"
echo "└── scan_metadata.txt  - Este archivo"
echo ""
echo "ARCHIVOS PRINCIPALES:"
echo "• executive_summary.txt  - Resumen ejecutivo"
echo "• nmap_results.json     - Resultados en formato JSON"
echo "• nmap_results.txt      - Resultados detallados en texto"
echo ""
echo "COMANDOS ÚTILES:"
echo "• Ver vulnerabilidades: grep -i 'vulnerable' $SCANS_DIR/results/nmap_results.txt"
echo "• Ver resumen: cat $SCANS_DIR/results/executive_summary.txt"
echo "• Ver logs: cat $SCANS_DIR/logs/scan_execution.log"
echo ""
echo "NOTA: Esta carpeta se eliminará automáticamente el:"
echo "      $(date -d "48 hours" '+%A, %d de %B de %Y a las %H:%M:%S')"
} > "$METADATA_FILE"

# Actualizar resumen ejecutivo
{
echo "========================================================"
echo "RESUMEN EJECUTIVO"
echo "========================================================"
echo "Fecha escaneo: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Carpeta resultados: $SCANS_DIR"
echo ""
echo "ESTADÍSTICAS:"
echo "• Total contenedores: $TOTAL_CONTAINERS"
echo "• Escaneos exitosos: $SUCCESS_SCANS"
echo "• Puertos abiertos: $TOTAL_OPEN_PORTS"
echo "• Vulnerabilidades: $TOTAL_VULNS"
echo ""
} > "$SUMMARY_FILE"

if [ $TOTAL_VULNS -gt 0 ]; then
    echo "¡ADVERTENCIA DE SEGURIDAD!" >> "$SUMMARY_FILE"
    echo "Se encontraron $TOTAL_VULNS vulnerabilidades potenciales." >> "$SUMMARY_FILE"
    echo "Revise los resultados detallados inmediatamente." >> "$SUMMARY_FILE"
else
    echo "No se detectaron vulnerabilidades en los escaneos." >> "$SUMMARY_FILE"
fi

{
echo ""
echo "ARCHIVOS GENERADOS:"
echo "• $SCANS_DIR/results/nmap_results.json"
echo "• $SCANS_DIR/results/nmap_results.txt"
echo "• $SCANS_DIR/logs/scan_execution.log"
echo ""
echo "El escaneo se completó correctamente."
echo "Esta carpeta será eliminada automáticamente en 48 horas."
} >> "$SUMMARY_FILE"

# Finalizar log
{
echo ""
echo "========================================================"
echo "ESCANEO COMPLETADO"
echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"
echo "Total contenedores procesados: $TOTAL_CONTAINERS"
echo "Escaneos exitosos: $SUCCESS_SCANS"
echo "Tiempo total estimado: ~$((TOTAL_CONTAINERS * 15)) minutos"
echo "Vulnerabilidades detectadas: $TOTAL_VULNS"
echo ""
echo "Resultados guardados en: $SCANS_DIR"
echo "========================================================"
} >> "$LOG_FILE"

echo ""
echo "========================================================"
echo "ESCANEOS COMPLETADOS"
echo "========================================================"
echo "Estadísticas:"
echo "  • Contenedores escaneados: $SUCCESS_SCANS/$TOTAL_CONTAINERS"
echo "  • Puertos abiertos encontrados: $TOTAL_OPEN_PORTS"
echo "  • Vulnerabilidades detectadas: $TOTAL_VULNS"
echo ""
echo "Resultados guardados en:"
echo "  📁 $SCANS_DIR/"
echo "  ├── 📄 results/nmap_results.json"
echo "  ├── 📄 results/nmap_results.txt"
echo "  ├── 📄 results/executive_summary.txt"
echo "  ├── 📄 logs/scan_execution.log"
echo "  ├── 📄 scan_metadata.txt"
echo "  └── 📂 raw/ (salidas crudas por contenedor)"
echo ""
echo "Limpieza automática programada para 48 horas."
echo ""
echo "Para ver vulnerabilidades:"
echo "  grep -i 'vulnerable' $SCANS_DIR/results/nmap_results.txt"
echo "========================================================"

# Mostrar mensaje de expiración
echo ""
echo "⚠️  NOTA: Esta carpeta será eliminada automáticamente el:"
echo "    $(date -d "48 hours" '+%A, %d de %B de %Y a las %H:%M:%S')"
echo ""
