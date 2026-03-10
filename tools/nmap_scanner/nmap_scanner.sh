#!/bin/bash
# nmap_vuln_scanner.sh - Escaneo con scripts de vulnerabilidad
# Versión: 2.4 - Versión optimizada (menos líneas, misma funcionalidad)

# ========================================================
# VERIFICACIÓN DE USUARIO ROOT
# ========================================================
if [ "$EUID" -ne 0 ]; then 
    echo "========================================================"
    echo "  ERROR: PERMISOS INSUFICIENTES"
    echo "========================================================"
    echo "  Este script debe ejecutarse como usuario root"
    echo "  Por favor, ejecute con: sudo ./$(basename "$0")"
    echo "========================================================"
    exit 1
fi

# ========================================================
# CONFIGURACIÓN DE DIRECTORIOS
# ========================================================
BASE_SCANS_DIR="nmap_scans"
mkdir -p "$BASE_SCANS_DIR"

# Generar nombre de directorio único
CURRENT_DATE=$(date '+%Y%m%d_%H%M%S')
SCANS_DIR="${BASE_SCANS_DIR}/nmap_scan_${CURRENT_DATE}"

# Si existe, añadir contador
COUNTER=1
while [ -d "$SCANS_DIR" ]; do
    SCANS_DIR="${BASE_SCANS_DIR}/nmap_scan_${CURRENT_DATE}_${COUNTER}"
    COUNTER=$((COUNTER + 1))
done

# Crear estructura de carpetas
mkdir -p "$SCANS_DIR"/{logs,results,raw}

echo "========================================================"
echo "ESCANEO NMAP DE VULNERABILIDADES"
echo "DIRECTORIO: $SCANS_DIR"
echo "========================================================"

# ========================================================
# LIMPIEZA AUTOMÁTICA (48 HORAS)
# ========================================================
if command -v at &>/dev/null; then
    echo "rm -rf $SCANS_DIR" | at now + 48 hours 2>/dev/null
    echo "[INFO] Limpieza automática programada para 48 horas"
else
    echo "[ADVERTENCIA] Instala 'at' para limpieza automática"
    echo "            Elimina manualmente: rm -rf $SCANS_DIR"
fi

# ========================================================
# VERIFICACIONES DEL SISTEMA
# ========================================================
if ! docker ps &>/dev/null; then
    echo "Error: Docker no está corriendo"
    exit 1
fi

if ! command -v nmap &>/dev/null; then
    echo "Instalando nmap..."
    apt update && apt install -y nmap
fi

# ========================================================
# ARCHIVOS DE SALIDA
# ========================================================
JSON_FILE="$SCANS_DIR/results/nmap_scanner.json"
TXT_FILE="$SCANS_DIR/results/nmap_scanner.txt"
LOG_FILE="$SCANS_DIR/logs/scan_execution.log"

# Inicializar archivos
{
    echo "========================================================"
    echo "LOG DE EJECUCIÓN - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Directorio: $SCANS_DIR"
    echo "========================================================"
} > "$LOG_FILE"

echo "{" > "$JSON_FILE"
echo '  "scan_type": "vulnerability_assessment",' >> "$JSON_FILE"
echo '  "timestamp": "'$(date -Iseconds)'",' >> "$JSON_FILE"
echo '  "scans": {' >> "$JSON_FILE"

{
    echo "========================================================"
    echo "ESCANEO DE VULNERABILIDADES NMAP"
    echo "FECHA: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "DIRECTORIO: $SCANS_DIR"
    echo "COMANDO: nmap -A -T4 -p- -sV -sC --script vuln"
    echo "========================================================"
    echo ""
} > "$TXT_FILE"

# ========================================================
# DETECCIÓN DE CONTENEDORES
# ========================================================
CONTAINERS=$(docker ps --format "{{.Names}}")
if [ -z "$CONTAINERS" ]; then
    echo "No hay contenedores corriendo" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Contenedores encontrados:" >> "$LOG_FILE"
for c in $CONTAINERS; do
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c" 2>/dev/null)
    img=$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null)
    echo "  - $c: $ip ($img)" | tee -a "$LOG_FILE"
done

# ========================================================
# VARIABLES PARA ESTADÍSTICAS
# ========================================================
FIRST=true
TOTAL_CONT=0
SUCCESS_SCANS=0
TOTAL_VULNS=0
TOTAL_PORTS=0

# ========================================================
# ESCANEO DE CONTENEDORES
# ========================================================
echo "" >> "$LOG_FILE"
echo "INICIANDO ESCANEOS..." >> "$LOG_FILE"

for CONTAINER in $CONTAINERS; do
    TOTAL_CONT=$((TOTAL_CONT + 1))
    
    # Obtener IP
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)
    
    if [ -z "$IP" ]; then
        echo "$CONTAINER: Sin IP válida" | tee -a "$LOG_FILE" "$TXT_FILE"
        continue
    fi
    
    IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER" 2>/dev/null)
    
    echo ""
    echo "========================================================"
    echo "ESCANEANDO: $CONTAINER ($IP) - $IMAGE"
    echo "========================================================"
    
    echo "[$(date '+%H:%M:%S')] Escaneando $CONTAINER..." >> "$LOG_FILE"
    
    # Separador JSON
    [ "$FIRST" = false ] && echo "," >> "$JSON_FILE"
    FIRST=false
    
    # Encabezado en TXT
    {
        echo ""
        echo "========================================================"
        echo "CONTENEDOR: $CONTAINER"
        echo "IP: $IP | Imagen: $IMAGE"
        echo "========================================================"
    } >> "$TXT_FILE"
    
    # Ejecutar nmap
    START_TIME=$(date +%s)
    RAW_FILE="$SCANS_DIR/raw/${CONTAINER}_$(date '+%H%M%S').txt"
    
    echo "Ejecutando nmap (puede tardar varios minutos)..."
    NMAP_OUTPUT=$(timeout 1200 nmap -A -T4 -p- -sV -sC --script vuln "$IP" 2>&1)
    RETURN_CODE=$?
    
    echo "$NMAP_OUTPUT" > "$RAW_FILE"
    
    END_TIME=$(date +%s)
    SCAN_TIME=$((END_TIME - START_TIME))
    
    # Análisis de resultados
    OPEN_PORTS=$(echo "$NMAP_OUTPUT" | grep -c "^[0-9]\+/tcp.*open")
    VULNERABILITIES=$(echo "$NMAP_OUTPUT" | grep -c "VULNERABLE:\|State: VULNERABLE")
    
    TOTAL_PORTS=$((TOTAL_PORTS + OPEN_PORTS))
    TOTAL_VULNS=$((TOTAL_VULNS + VULNERABILITIES))
    
    if [ $RETURN_CODE -eq 0 ]; then
        SUCCESS_SCANS=$((SUCCESS_SCANS + 1))
        STATUS="COMPLETADO"
    elif [ $RETURN_CODE -eq 124 ]; then
        STATUS="TIMEOUT"
    else
        STATUS="ERROR"
    fi
    
    # Mostrar resumen
    echo "  Puertos: $OPEN_PORTS | Vulnerabilidades: $VULNERABILITIES | Tiempo: ${SCAN_TIME}s"
    echo "[$(date '+%H:%M:%S')] $CONTAINER: $STATUS (${SCAN_TIME}s)" >> "$LOG_FILE"
    
    # Guardar en JSON
    cat >> "$JSON_FILE" <<EOF
    "$CONTAINER": {
      "ip": "$IP",
      "image": "$IMAGE",
      "status": "$STATUS",
      "scan_time": $SCAN_TIME,
      "return_code": $RETURN_CODE,
      "ports_open": $OPEN_PORTS,
      "vulnerabilities": $VULNERABILITIES,
      "raw_file": "$(basename $RAW_FILE)"
    }
EOF
    
    # Guardar en TXT
    {
        echo "ESTADO: $STATUS"
        echo "TIEMPO: ${SCAN_TIME}s"
        echo "PUERTOS ABIERTOS: $OPEN_PORTS"
        echo "VULNERABILIDADES: $VULNERABILITIES"
        echo ""
        
        if [ $OPEN_PORTS -gt 0 ]; then
            echo "DETALLE DE PUERTOS:"
            echo "$NMAP_OUTPUT" | grep "^[0-9]\+/tcp.*open" | head -10
            echo ""
        fi
        
        if [ $VULNERABILITIES -gt 0 ]; then
            echo "VULNERABILIDADES DETECTADAS:"
            echo "$NMAP_OUTPUT" | grep -E "VULNERABLE:|State: VULNERABLE" | head -10
            echo ""
        fi
        
        echo "--- FIN ESCANEO ---"
    } >> "$TXT_FILE"
    
    # Pausa entre escaneos
    sleep 5
done

# ========================================================
# FINALIZACIÓN
# ========================================================
# Cerrar JSON
cat >> "$JSON_FILE" <<EOF
  },
  "statistics": {
    "total_containers": $TOTAL_CONT,
    "successful_scans": $SUCCESS_SCANS,
    "total_ports": $TOTAL_PORTS,
    "total_vulnerabilities": $TOTAL_VULNS,
    "completion_date": "$(date -Iseconds)"
  }
}
EOF

# Añadir estadísticas al TXT
{
    echo ""
    echo "========================================================"
    echo "ESTADÍSTICAS GLOBALES"
    echo "========================================================"
    echo "Contenedores totales: $TOTAL_CONT"
    echo "Escaneos exitosos: $SUCCESS_SCANS"
    echo "Puertos abiertos totales: $TOTAL_PORTS"
    echo "Vulnerabilidades encontradas: $TOTAL_VULNS"
    echo ""
    echo "Resultados guardados en: $SCANS_DIR"
    echo "========================================================"
} >> "$TXT_FILE"

# Crear archivo de metadatos
{
    echo "========================================================"
    echo "METADATOS DEL ESCANEO"
    echo "========================================================"
    echo "Fecha creación: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Directorio: $SCANS_DIR"
    echo "Fecha expiración: $(date -d "48 hours" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "No programada")"
    echo "Contenedores escaneados: $SUCCESS_SCANS/$TOTAL_CONT"
    echo "Vulnerabilidades: $TOTAL_VULNS"
    echo ""
    echo "ARCHIVOS GENERADOS:"
    echo "  results/nmap_scanner.json"
    echo "  results/nmap_scanner.txt"
    echo "  logs/scan_execution.log"
    echo "  raw/ (salidas crudas)"
    echo ""
    echo "COMANDOS ÚTILES:"
    echo "  grep -i 'vulnerable' $SCANS_DIR/results/nmap_scanner.txt"
} > "$SCANS_DIR/scan_metadata.txt"

# Finalizar log
{
    echo ""
    echo "========================================================"
    echo "ESCANEO COMPLETADO - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Contenedores: $TOTAL_CONT | Exitosos: $SUCCESS_SCANS"
    echo "Vulnerabilidades: $TOTAL_VULNS"
    echo "========================================================"
} >> "$LOG_FILE"

# Mostrar resumen final
echo ""
echo "========================================================"
echo "ESCANEO COMPLETADO"
echo "========================================================"
echo "  Contenedores: $SUCCESS_SCANS/$TOTAL_CONT"
echo "  Puertos totales: $TOTAL_PORTS"
echo "  Vulnerabilidades: $TOTAL_VULNS"
echo ""
echo "Resultados:"
echo "  $SCANS_DIR/"
echo "  ├── results/nmap_scanner.json"
echo "  ├── results/nmap_scanner.txt"
echo "  ├── logs/scan_execution.log"
echo "  └── raw/"
echo ""
echo "Para ver vulnerabilidades:"
echo "  grep -i 'vulnerable' $SCANS_DIR/results/nmap_scanner.txt"
echo "========================================================"

if command -v date &>/dev/null; then
    echo ""
    echo "NOTA: Esta carpeta expirará el:"
    echo "  $(date -d "48 hours" '+%A, %d de %B de %Y a las %H:%M:%S' 2>/dev/null || echo "En 48 horas")"
fi
echo ""
