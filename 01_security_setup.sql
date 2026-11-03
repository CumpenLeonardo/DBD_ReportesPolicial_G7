-- =============================================================================
-- 01_security_setup.sql | Ejecutar como SYS (SYSDBA) en el PDB destino
-- =============================================================================
-- PROPÓSITO
--   Crea la infraestructura de seguridad y almacenamiento del sistema:
--     * 1 tablespace donde se guardan los datos de GEO-DENUNCIA.
--     * 3 roles con distintos niveles de permiso (principio de mínimo privilegio).
--     * 3 usuarios, cada uno con un rol distinto.
--
-- MODELO DE SEGURIDAD
--   GEO_OWNER    Dueño del esquema: es quien crea tablas, secuencias y paquetes.
--                No se usa desde la aplicación.
--   GEO_APP      Usuario con el que se conecta la aplicación Java (NetBeans).
--                Tiene el rol operador: puede leer, insertar y actualizar, y
--                ejecutar los paquetes, pero NO borrar filas directamente.
--   GEO_AUDITOR  Usuario de consulta (auditoría o reportes): solo lectura.
--
-- Los permisos sobre tablas y paquetes no se dan aquí porque todavía no existen,
-- se otorgan en 40_grants_roles.sql.
-- =============================================================================

-- Ruta donde Oracle guardará el archivo de datos. Debe existir en el servidor.
DEFINE data_dir = 'C:\APP\ORADATA\XEPDB1'
ACCEPT app_pass     CHAR PROMPT 'Password for GEO_APP: ' HIDE
ACCEPT auditor_pass CHAR PROMPT 'Password for GEO_AUDITOR: ' HIDE

-- Tablespace: espacio físico de almacenamiento. Empieza en 200 MB y crece de
-- 50 MB en 50 MB hasta un máximo de 2 GB.
CREATE TABLESPACE ts_geo_data
  DATAFILE '&data_dir\ts_geo_data01.dbf' SIZE 200M AUTOEXTEND ON NEXT 50M MAXSIZE 2G;

-- Roles: agrupan permisos para asignarlos a usuarios sin repetirlos uno por uno.
CREATE ROLE role_geo_admin;      -- administrador: SELECT/INSERT/UPDATE/DELETE y EXECUTE en todos los paquetes
CREATE ROLE role_geo_operator;   -- operador: SELECT/INSERT/UPDATE y EXECUTE en los paquetes de negocio
CREATE ROLE role_geo_readonly;   -- consulta: solo SELECT
GRANT CREATE SESSION TO role_geo_admin, role_geo_operator, role_geo_readonly;  -- permite iniciar sesión

-- Dueño del esquema. QUOTA UNLIMITED le permite usar todo el tablespace.
CREATE USER geo_owner IDENTIFIED BY "&owner_pass"
  DEFAULT TABLESPACE ts_geo_data QUOTA UNLIMITED ON ts_geo_data;
-- Privilegios de sistema que necesita para construir y mantener el esquema.
GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE PROCEDURE,
      CREATE TRIGGER, CREATE VIEW TO geo_owner;

-- Usuario de la aplicación Java: recibe el rol operador.
CREATE USER geo_app IDENTIFIED BY "&app_pass" DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_operator TO geo_app;

-- Usuario de auditoría: recibe el rol de solo lectura.
CREATE USER geo_auditor IDENTIFIED BY "&auditor_pass" DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_readonly TO geo_auditor;
