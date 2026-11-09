-- =============================================================================
-- 01_security_setup.sql
-- Crea el tablespace, los roles y los usuarios. Los permisos sobre tablas se
--   GEO_OWNER: Crea y es dueño de todos los objetos
--   GEO_APP: Aplicación Java: lee, inserta, actualiza y ejecuta paquetes
--   GEO_AUDITOR: Solo lectura, sin ver denunciantes anónimos
--   GEO_CHIEF: Jefes de alto rango: lectura total, incluye la identidad de denunciantes anónimos
-- =============================================================================
DEFINE data_dir = 'C:\APP\ORADATA\XEPDB1'
ACCEPT app_pass     CHAR PROMPT 'Password for GEO_APP: ' HIDE
ACCEPT auditor_pass CHAR PROMPT 'Password for GEO_AUDITOR: ' HIDE
ACCEPT chief_pass   CHAR PROMPT 'Password for GEO_CHIEF: ' HIDE

-- Espacio de almacenamiento de las tablas. Empieza en 200 MB y crece hasta 2 GB.
CREATE TABLESPACE ts_geo_data
  DATAFILE '&data_dir\ts_geo_data01.dbf' SIZE 200M AUTOEXTEND ON NEXT 50M MAXSIZE 2G;

-- Roles: agrupan permisos para asignarlos a los usuarios.
CREATE ROLE role_geo_admin;
CREATE ROLE role_geo_operator;
CREATE ROLE role_geo_readonly;
CREATE ROLE role_geo_chief;
GRANT CREATE SESSION TO role_geo_admin, role_geo_operator, role_geo_readonly, role_geo_chief;

-- Dueño del esquema, con los privilegios para construirlo.
CREATE USER geo_owner IDENTIFIED BY "&owner_pass"
  DEFAULT TABLESPACE ts_geo_data QUOTA UNLIMITED ON ts_geo_data;
GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE PROCEDURE, CREATE TRIGGER, CREATE VIEW TO geo_owner;

CREATE USER geo_app IDENTIFIED BY "&app_pass" DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_operator TO geo_app;

CREATE USER geo_auditor IDENTIFIED BY "&auditor_pass" DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_readonly TO geo_auditor;

-- El rol de jefe solo debe darse a cuentas de mandos autorizados a ver la identidad de denunciantes anónimos.

CREATE USER geo_chief IDENTIFIED BY "&chief_pass" DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_chief TO geo_chief;
