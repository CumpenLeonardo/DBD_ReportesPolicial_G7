-- =============================================================================
-- 00_run_all.sql | Script maestro: reconstruye la base de datos desde cero
-- Uso (desde la carpeta de los scripts, en una terminal): sqlplus /nolog @00_run_all.sql
-- Todo lo que ocurre queda guardado en install_log.txt.
--
--   01_security_setup.sql   tablespace, roles y usuarios (como SYS)
--   02_pkg_db_installer.sql instalador que limpia el esquema
--   10_schema.sql           tablas, restricciones, índices, secuencias y triggers
--   20_packages.sql         paquetes pkg_org_mgmt, pkg_cpl_mgmt y pkg_inv_mgmt
--   30_data.sql             datos de prueba (va después de los paquetes porque los usa)
--   40_grants_roles.sql     permisos de los roles y vista de denunciantes
--   50_tests.sql            pruebas automáticas (hacen ROLLBACK)
--   99_verify.sql           revisión final
-- =============================================================================
SET DEFINE ON            -- por si una carga anterior en esta sesión lo desactivó
SET SQLBLANKLINES ON     -- necesario: varios scripts tienen líneas en blanco dentro de un CREATE
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
SET LINESIZE 200
SET PAGESIZE 100
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

ACCEPT service    CHAR PROMPT 'Service (e.g. localhost:1521/XEPDB1): '
ACCEPT sys_pass   CHAR PROMPT 'SYS password: ' HIDE
ACCEPT owner_pass CHAR PROMPT 'Password for GEO_OWNER: ' HIDE

SPOOL install_log.txt

-- Como administrador: tablespace, roles y usuarios.
CONNECT sys/&sys_pass@&service AS SYSDBA
@@01_security_setup.sql

-- Como dueño del esquema: limpieza de cualquier instalación previa y creación de todo.
CONNECT geo_owner/&owner_pass@&service
@@02_pkg_db_installer.sql
EXEC pkg_db_installer.drop_all_objects;

@@10_schema.sql
@@20_packages.sql
@@30_data.sql
@@40_grants_roles.sql
@@50_tests.sql
@@99_verify.sql

SPOOL OFF
