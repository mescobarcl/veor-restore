# Preparación de Base de Datos Oracle para Recuperación con Veeam Explorer

Script automatizado para preparar instancias de base de datos Oracle para recuperación usando Veeam Explorer for Oracle RMAN. Este script simplifica el complejo proceso de configurar un entorno Oracle para restauración de base de datos manteniendo el DBID original.

## 🚀 Características

- **Configuración Automatizada del Entorno**: Crea todos los directorios, archivos de parámetros y configuraciones necesarias
- **Configuración Interactiva**: Indicaciones amigables que guían a través de todo el proceso de configuración
- **Detección de Oracle Home**: Detecta automáticamente las versiones de Oracle instaladas
- **Restauración de Control Files**: Soporte integrado para restaurar control files desde backups de Veeam
- **Creación de SPFILE**: Crea automáticamente el SPFILE desde PFILE para compatibilidad con Veeam Explorer
- **Registro Completo**: Registro detallado de todas las operaciones para resolución de problemas
- **Scripts de Verificación**: Genera scripts de utilidad para verificar la configuración

## 📋 Requerimientos

- **Sistema Operativo**: Linux (RHEL, OEL, CentOS)
- **Software Oracle**: Oracle Database instalado 
- **Software Veeam**: 
  - Veeam Backup & Replication (con licencia para plugin Oracle RMAN)
  - Veeam Plugin for Oracle RMAN instalado en el servidor destino
- **Usuario**: Debe ejecutarse como usuario `oracle`
- **Datos Requeridos**: 
  - DBID de la base de datos original
  - Acceso al repositorio de backup de Veeam
  - Token de Recuperación del backup

## 🔧 Instalación

1. Descargar el script:
```bash
wget https://github.com/mescobarcl/veor-restore/raw/master/prepare-restore-veor.sh
```

2. Hacer el script ejecutable:
```bash
chmod +x prepare-restore-veor.sh
```

## 📖 Uso

Ejecutar el script como usuario oracle:
```bash
./prepare-restore-veor.sh
```

### Indicaciones Interactivas

El script te guiará a través de la siguiente información:

1. **Oracle SID**: El identificador del sistema para tu base de datos (ej: PRODDB)
2. **Oracle Home**: Detección automática o manualmente
3. **DBID Original**: El DBID de la base de datos fuente
4. **Contraseña SYS**: Elegir de opciones seguras predefinidas o crear personalizada
5. **Tamaño de Memoria**: Asignación de memoria para la instancia (por defecto: 2G)

### Ejecución de Ejemplo

```
===============================================
  ORACLE PREPARATION FOR VEEAM EXPLORER
===============================================

Enter Oracle SID (e.g. AUSTIN): PRODDB
Detecting installed Oracle versions...

Oracle Homes found:
1. /u01/app/oracle/product/19.0.0/dbhome_1 [19.0.0]
Select Oracle Home (1-1): 1

Enter the original database DBID: 3435226265

Select a password for SYS user:
1. Welcome#123_DB
2. PRODDB$2025_Db
3. Veeam@Recovery_19c
4. Oracle#Restore_2025
5. Enter custom password
Select an option (1-5) [1]: 1

Memory size for instance (e.g. 2G, 4G) [2G]: 4G
```

## 🔄 Qué Hace el Script

### 1. Preparación del Entorno
- Crea la estructura de carpetas de Oracle
- Configura variables de entorno en `.bash_profile`
- Crea el archivo de parámetros inicial (init.ora)
- Genera el archivo de contraseñas

### 2. Configuración de la Instancia
- Cierra cualquier instancia existente con el mismo SID
- Configura el Oracle Listener para conectividad de red
- Configura la resolución de nombres TNS

### 3. Integración con Veeam
- Configura la autenticación del Plugin Oracle de Veeam
- Ayuda con la restauración del control file desde el backup
- Crea el SPFILE

### 4. Verificación
- Genera script de verificación
- Guarda la información de recuperación de forma segura
- Proporciona un resumen detallado

## 📁 Archivos que Crea el Script

```
$ORACLE_HOME/dbs/
├── init${ORACLE_SID}.ora      # Archivo de parámetros
├── spfile${ORACLE_SID}.ora    # Archivo de parámetros del servidor
├── orapw${ORACLE_SID}         # Archivo de contraseñas
└── .${ORACLE_SID}_info.txt    # Información de recuperación (asegurado)

$ORACLE_BASE/admin/${ORACLE_SID}/
├── adump/                     # Carpeta de archivos de auditoría
├── pfile/                     # Respaldo de archivos de parámetros
└── scripts/
    └── verify_${ORACLE_SID}.sh # Script de verificación

$ORACLE_BASE/oradata/${ORACLE_SID}/
├── control01.ctl             # Control file 1 (después de restaurar)
└── control02.ctl             # Control file 2 (después de restaurar)
```

## 🛠️ Después de Ejecutar el Script

### Usar Veeam Explorer

1. Abrir la Consola de Veeam Backup & Replication
2. Click derecho en el backup de Oracle → "Restore application items" → "Oracle databases"
3. Configurar Base de Datos Destino:
   - **Oracle home**: Como se muestra en el término del script
   - **Database SID**: El SID
   - **Database state**: "Database is shut down"
   - **Credentials**: usuario oracle o SYS con la contraseña proporcionada

### Restauración Manual del Control File (si es necesario)

Si la restauración automática del control file falla:

```bash
rman target /

RMAN> STARTUP NOMOUNT;
RMAN> SET DBID=DBID-ORIGINAL;
RMAN> RUN {
        ALLOCATE CHANNEL ch1 TYPE sbt_tape PARMS
        'SBT_LIBRARY=/opt/veeam/VeeamPluginforOracleRMAN/libOracleRMANPlugin.so';
        SEND 'srcBackup=BACKUP-ID-ORIGINAL';
        RESTORE CONTROLFILE FROM 'nombre-control-file';
      }
RMAN> SHUTDOWN IMMEDIATE;
RMAN> EXIT;
```

## 🔍 Solución de Problemas

### Problemas Comunes

1. **Error ORA-00205 en Veeam Explorer**
   - Asegúrate de que los control files estén restaurados antes de usar Veeam Explorer
   - Verifica que el SPFILE se creó exitosamente

2. **Error de Complejidad de Contraseña**
   - Usa las opciones de contraseña proporcionadas o asegúrate de que la contraseña personalizada cumple los requisitos de Oracle
   - Mínimo 8 caracteres con mayúsculas, minúsculas, números y caracteres especiales

3. **Proceso Aún Activo**
   - Verifica procesos Oracle: `ps -ef | grep ORACLE_SID` o `ps -fea | grep pmon`
   - Terminar manualmente si es necesario: `kill -9 PID`

### Archivos de Log

- **Log del Script**: `/tmp/prepare_oracle_veeam_YYYYMMDD_HHMMSS.log`
- **Alert Log de Oracle**: `$ORACLE_BASE/diag/rdbms/$ORACLE_SID/$ORACLE_SID/trace/alert_$ORACLE_SID.log`

## 📝 Licencia

Este script se proporciona tal cual y no tiene ninguna garantía y/o soporte

## 🤝 Contribuciones

¡Las contribuciones son bienvenidas! Genera un Issue.
