-- =============================================================================
-- 01_security_setup.sql | Run as SYS (00_run_all.sql does it)
-- Creates the tablespace, roles and users. Table permissions are
-- granted later, in 40_grants_roles.sql.
--   GEO_OWNER: Creates and owns all objects
--   GEO_APP: Java application: reads, inserts, updates and runs packages
--   GEO_AUDITOR: Read-only, cannot see anonymous reporters
--   GEO_CHIEF: Senior commanders: full read access, including the identity of anonymous reporters
--
-- Re-runnable: first drops the users, roles and tablespace of a previous
-- installation. Close the connections of the GEO_* users before running it again
-- (otherwise Oracle answers ORA-01940).
-- =============================================================================
ACCEPT app_pass     CHAR PROMPT 'Password for GEO_APP: ' HIDE
ACCEPT auditor_pass CHAR PROMPT 'Password for GEO_AUDITOR: ' HIDE
ACCEPT chief_pass   CHAR PROMPT 'Password for GEO_CHIEF: ' HIDE

-- Cleanup of a previous installation (order: users, roles, tablespace).
BEGIN
  FOR u IN (SELECT username FROM dba_users
             WHERE username IN ('GEO_OWNER', 'GEO_APP', 'GEO_AUDITOR', 'GEO_CHIEF')) LOOP
    EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
  END LOOP;

  FOR r IN (SELECT role FROM dba_roles
             WHERE role IN ('ROLE_GEO_ADMIN', 'ROLE_GEO_OPERATOR', 'ROLE_GEO_READONLY', 'ROLE_GEO_CHIEF')) LOOP
    EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
  END LOOP;

  FOR t IN (SELECT tablespace_name FROM dba_tablespaces
             WHERE tablespace_name = 'TS_GEO_DATA') LOOP
    EXECUTE IMMEDIATE 'DROP TABLESPACE ' || t.tablespace_name || ' INCLUDING CONTENTS AND DATAFILES';
  END LOOP;
END;
/

-- Storage space for the tables. Starts at 200 MB and grows up to 2 GB.
-- The folder is taken from where this database's SYSTEM datafile already is, so the
-- script does not depend on a fixed path and works the same on Windows, Linux and Docker.
DECLARE
  v_file VARCHAR2(512);
  v_dir  VARCHAR2(512);
BEGIN
  SELECT file_name INTO v_file
    FROM dba_data_files
   WHERE tablespace_name = 'SYSTEM' AND ROWNUM = 1;

  -- Folder = everything up to the last separator ('/' on Linux, '\' on Windows).
  v_dir := SUBSTR(v_file, 1, GREATEST(INSTR(v_file, '/', -1), INSTR(v_file, '\', -1)));

  IF v_dir IS NULL THEN
    -- No recognizable folder: let Oracle choose (Oracle Managed Files).
    EXECUTE IMMEDIATE 'CREATE TABLESPACE ts_geo_data DATAFILE SIZE 200M AUTOEXTEND ON NEXT 50M MAXSIZE 2G';
  ELSE
    EXECUTE IMMEDIATE 'CREATE TABLESPACE ts_geo_data DATAFILE ''' || v_dir
                      || 'ts_geo_data01.dbf'' SIZE 200M AUTOEXTEND ON NEXT 50M MAXSIZE 2G';
  END IF;
END;
/

-- Roles: group permissions so they can be assigned to users.
CREATE ROLE role_geo_admin;
CREATE ROLE role_geo_operator;
CREATE ROLE role_geo_readonly;
CREATE ROLE role_geo_chief;
GRANT CREATE SESSION TO role_geo_admin, role_geo_operator, role_geo_readonly, role_geo_chief;

-- Schema owner, with the privileges to build it.
CREATE USER geo_owner IDENTIFIED BY "&owner_pass"
  DEFAULT TABLESPACE ts_geo_data QUOTA UNLIMITED ON ts_geo_data;
GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE PROCEDURE, CREATE TRIGGER, CREATE VIEW TO geo_owner;

CREATE USER geo_app IDENTIFIED BY "&app_pass" DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_operator TO geo_app;

CREATE USER geo_auditor IDENTIFIED BY "&auditor_pass" DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_readonly TO geo_auditor;

-- The chief role must only be given to accounts of commanders authorized to see the identity of anonymous reporters.
CREATE USER geo_chief IDENTIFIED BY "&chief_pass" DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_chief TO geo_chief;
