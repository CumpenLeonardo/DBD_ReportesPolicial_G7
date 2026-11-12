# Sistema de Gestión y Georreferenciación de Denuncias Policiales (Grupo 7)

Repositorio oficial de scripts DDL, DML, programación almacenada en PL/SQL y pruebas automatizadas sobre **Oracle Database** (con soporte espacial **Oracle Spatial / SDO_GEOMETRY**) para la Entrega Parcial 2 del curso de Administración de Base de Datos.

---

## 1. Sustento Técnico: ¿Por qué optamos por una arquitectura modular en lugar de un único archivo?

Como equipo, comprendemos perfectamente que la finalidad de solicitar un archivo único es **garantizar una instalación automática, portable y en un solo paso** en cualquier computadora, evitando ejecuciones manuales desordenadas o dependencias rotas. 

Sin embargo, tras analizar el alcance real de nuestro sistema (más de 2,500 líneas de código entre 18 tablas, 4 paquetes PL/SQL, 7 triggers, 4 vistas gerenciales, carga de 80 denuncias georreferenciadas y 64 pruebas unitarias), **decidimos estructurar el proyecto en 9 scripts modulares numerados secuencialmente (`00` al `99`) y orquestados por un único script maestro (`00_run_all.sql`)** por cuatro razones técnicas fundamentales:

1. **Separación de privilegios y contextos de sesión (`SYSDBA` vs. `GEO_OWNER`):** En Oracle Database, la creación de *tablespaces*, roles y usuarios debe ejecutarse con privilegios de administrador (`SYS AS SYSDBA`), mientras que todos los objetos del negocio (tablas, índices, paquetes y triggers) deben pertenecer exclusivamente al propietario del esquema (`GEO_OWNER`) bajo el principio de mínimo privilegio. Mezclar ambos contextos en un único archivo monolítico dificulta el aislamiento de permisos y el control de errores por sesión.
2. **Idempotencia y despliegue limpio en cualquier entorno (Local o Docker):** Al aislar la configuración de almacenamiento en `01_security_setup.sql` (con detección dinámica de *Oracle Managed Files* —OMF— y cláusula `REUSE`) y la limpieza de objetos en `02_pkg_db_installer.sql`, garantizamos que el sistema pueda reinstalarse desde cero cuantas veces sea necesario sin colisiones de archivos físicos (`ORA-01537`) ni sesiones activas (`ORA-01940`).
3. **Mantenibilidad, trazabilidad y trabajo colaborativo:** Dividir el código por capas lógicas (seguridad, estructura, paquetes, datos, permisos y pruebas) nos permitió trabajar en paralelo mediante control de versiones en Git sin conflictos de fusión (*merge conflicts*), facilitando además la auditoría directa de cada componente durante la revisión académica.
4. **Cumplimiento del despliegue en un solo paso mediante orquestación:** Con nuestro script maestro **`00_run_all.sql`**, conservamos la ventaja exacta que se busca con un archivo único: **basta ejecutar un solo comando en consola** para que Oracle conecte las sesiones necesarias, construya toda la base de datos en cascada, ejecute las 64 pruebas unitarias y guarde la evidencia completa en `install_log.txt`.

---

## 2. Estructura de Archivos del Repositorio

Los scripts están numerados según su orden estricto de dependencia:

| Archivo | Capa / Función | Contexto de Ejecución |
| :--- | :--- | :---: |
| **`00_run_all.sql`** | **Script maestro orquestador.** Automatiza toda la instalación de principio a fin y genera `install_log.txt`. | `SYSDBA` $\rightarrow$ `GEO_OWNER` |
| **`01_security_setup.sql`** | Crea el tablespace `TS_GEO_DATA` (compatible con OMF/Docker y `REUSE`), los 4 roles y los 4 usuarios del sistema. | `SYS AS SYSDBA` |
| **`02_pkg_db_installer.sql`** | Crea el paquete `PKG_DB_INSTALLER` (`drop_all_objects`) para limpiar cualquier instalación previa del esquema. | `GEO_OWNER` |
| **`10_schema.sql`** | Crea las 18 tablas, restricciones (`PK`, `FK`, `UK`, `CK`), índices B-Tree, índices espaciales R-Tree, índice único condicional, 16 secuencias y 7 triggers. | `GEO_OWNER` |
| **`20_packages.sql`** | Compila los 3 paquetes de lógica de negocio: `PKG_ORG_MGMT`, `PKG_CPL_MGMT` y `PKG_INV_MGMT`. | `GEO_OWNER` |
| **`30_data.sql`** | Puebla datos maestros (monedas, divisiones, comisarías, 6 sectores con polígonos, 10 oficiales, canales, juntas vecinales), 80 denuncias y transiciones de investigación/operativos. | `GEO_OWNER` |
| **`40_grants_roles.sql`** | Crea las 4 vistas gerenciales (`VW_CPL_REPORTER_PUBLIC`, `VW_INV_CASE_TRACKING`, `VW_STAFF_WORKLOAD`, `VW_TERR_SECTOR_SITUATION`) y asigna los 26 privilegios a los roles. | `GEO_OWNER` |
| **`50_tests.sql`** | Ejecuta la suite de **64 pruebas unitarias automatizadas** (finaliza con `ROLLBACK` para no alterar los datos semilla). | `GEO_OWNER` |
| **`99_verify.sql`** | Realiza la auditoría post-instalación: objetos inválidos, errores de compilación, inventario, conteo de filas y consistencia espacial/transaccional. | `GEO_OWNER` |

---

## 3. Guía de Instalación en su Computadora

### Requisitos Previos
* **Oracle Database** (19c, 21c o 23ai Free) en ejecución (instalación local o contenedor Docker) con soporte **Oracle Spatial / Locator** activo (incluido por defecto en Oracle XE / Free / EE).
* **SQL\*Plus** disponible en la terminal del sistema operativo (incluido en cualquier instalación de Oracle Database o Oracle Instant Client).

---

### Método 1: Instalación Automática en un Solo Paso (Recomendado)

Este método utiliza el orquestador `00_run_all.sql` para desplegar, poblar, probar y auditar toda la base de datos sin intervención manual:

1. **Descargar el repositorio:**
   * Clone el repositorio o descárguelo como ZIP (`Code > Download ZIP`) y descomprímalo en una carpeta local.
2. **Abrir una terminal (CMD, PowerShell o Bash) y ubicarse dentro de la carpeta que contiene los archivos `.sql`:**
   ```bash
   cd ruta/a/DBD_ReportesPolicial_G7-Script-FINAL
Ejecutar el script maestro con SQL*Plus:

Bash
sqlplus /nolog @00_run_all.sql
Ingresar los parámetros solicitados en pantalla:

Service: Cadena de conexión hacia su base de datos conectable (PDB), por ejemplo: localhost:1521/FREEPDB1 o localhost:1521/XEPDB1.

SYS password: Contraseña de su usuario administrador SYS.

Password for GEO_OWNER: Contraseña que desea asignar al propietario del esquema (ej. oracle123).

Seguidamente, el instalador le solicitará las contraseñas para los usuarios de aplicación (GEO_APP, GEO_CHIEF y GEO_AUDITOR).

Al finalizar (en aproximadamente 10 a 15 segundos), el proceso terminará automáticamente y dejará toda la traza registrada en el archivo install_log.txt dentro de la misma carpeta.

Método 2: Ejecución desde Oracle SQL Developer (Alternativo)
Si prefiere ejecutar los scripts desde la interfaz gráfica de Oracle SQL Developer (dado que el comando CONNECT interactivo de 00_run_all.sql está diseñado para terminal):

Conéctese como SYS (Rol: SYSDBA), abra 01_security_setup.sql y ejecútelo como script presionando F5 (ingrese las contraseñas solicitadas en los cuadros emergentes).

Cree una nueva conexión para el usuario GEO_OWNER (usando la contraseña definida en el paso anterior y el mismo servicio PDB).

Conectado como GEO_OWNER, abra y ejecute con F5 cada script en estricto orden numérico:

02_pkg_db_installer.sql (y ejecute EXEC pkg_db_installer.drop_all_objects; si desea limpiar una instalación previa)

10_schema.sql

20_packages.sql

30_data.sql

40_grants_roles.sql

50_tests.sql

99_verify.sql

4. Verificación de Instalación Exitosa
Al concluir la ejecución de 99_verify.sql, el sistema confirmará los siguientes indicadores de integridad:

Objetos inválidos: 0

Errores de compilación: 0

Inventario desplegado: 18 tablas, 16 secuencias explícitas (SEQ_*), 4 vistas, 4 paquetes (con sus 4 cuerpos) y 7 triggers.

Pruebas automatizadas (50_tests.sql): 64 PASS, 0 FAIL (23 en Denuncias, 12 en Organización/Territorio, 21 en Investigación/Operativos y 8 en Vistas de Gestión).

Consistencia espacial y operativa: SECTORES_SIN_POLIGONO = 0, CONTADORES_INCORRECTOS = 0 y DENUNCIAS_SIN_GEOMETRIA = 0.
