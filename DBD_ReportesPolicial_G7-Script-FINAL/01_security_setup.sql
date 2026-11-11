-- =============================================================================
-- 01_security_setup.sql | Execute connected as SYSDBA
-- =============================================================================

ACCEPT app_pass     CHAR PROMPT 'Password for GEO_APP: ' HIDE
ACCEPT auditor_pass CHAR PROMPT 'Password for GEO_AUDITOR: ' HIDE
ACCEPT chief_pass   CHAR PROMPT 'Password for GEO_CHIEF: ' HIDE

-- =============================================================================
-- 1. CLEANUP (allows clean re-installation)
-- =============================================================================
SET SERVEROUTPUT ON;

BEGIN
  DBMS_OUTPUT.PUT_LINE('-> Terminating existing sessions, users, roles, and tablespace...');

  -- Kill active sessions (avoids ORA-01940)
  FOR s IN (
    SELECT sid, serial# 
    FROM v$session 
    WHERE username IN ('GEO_OWNER', 'GEO_APP', 'GEO_AUDITOR', 'GEO_CHIEF')
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- Drop users
  FOR u IN (
    SELECT username 
    FROM all_users 
    WHERE username IN ('GEO_OWNER', 'GEO_APP', 'GEO_AUDITOR', 'GEO_CHIEF')
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- Drop roles
  FOR r IN (
    SELECT role 
    FROM dba_roles 
    WHERE role IN ('ROLE_GEO_ADMIN', 'ROLE_GEO_OPERATOR', 'ROLE_GEO_READONLY', 'ROLE_GEO_CHIEF')
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- Drop tablespace
  FOR ts IN (
    SELECT tablespace_name 
    FROM dba_tablespaces 
    WHERE tablespace_name = 'TS_GEO_DATA'
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLESPACE ts_geo_data INCLUDING CONTENTS AND DATAFILES CASCADE CONSTRAINTS';
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/

-- =============================================================================
-- 2. TABLESPACE (OMF or relative path)
-- =============================================================================
DECLARE
  v_omf VARCHAR2(512);
BEGIN
  -- Check whether OMF is enabled
  BEGIN
    SELECT value INTO v_omf 
    FROM v$parameter 
    WHERE name = 'db_create_file_dest';
  EXCEPTION 
    WHEN OTHERS THEN v_omf := NULL;
  END;

  IF v_omf IS NOT NULL THEN
      -- OMF: Oracle chooses the path
      EXECUTE IMMEDIATE 'CREATE TABLESPACE ts_geo_data DATAFILE SIZE 200M AUTOEXTEND ON NEXT 50M MAXSIZE 2G';
    ELSE
      -- No OMF: relative filename; REUSE tolerates leftover datafiles
      EXECUTE IMMEDIATE 'CREATE TABLESPACE ts_geo_data DATAFILE ''ts_geo_data01.dbf'' SIZE 200M REUSE AUTOEXTEND ON NEXT 50M MAXSIZE 2G';
    END IF;

  DBMS_OUTPUT.PUT_LINE('-> Tablespace TS_GEO_DATA created successfully.');
END;
/

-- =============================================================================
-- 3. ROLES AND SESSION PRIVILEGE
-- =============================================================================
CREATE ROLE role_geo_admin;
CREATE ROLE role_geo_operator;
CREATE ROLE role_geo_readonly;
CREATE ROLE role_geo_chief;

GRANT CREATE SESSION TO role_geo_admin, role_geo_operator, role_geo_readonly, role_geo_chief;

-- =============================================================================
-- 4. USERS AND QUOTAS
-- =============================================================================

-- Schema owner
CREATE USER geo_owner IDENTIFIED BY "&owner_pass"
  DEFAULT TABLESPACE ts_geo_data 
  QUOTA UNLIMITED ON ts_geo_data;

GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE PROCEDURE, 
      CREATE TRIGGER, CREATE VIEW TO geo_owner;

-- Application user (Java client)
CREATE USER geo_app IDENTIFIED BY "&app_pass" 
  DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_operator TO geo_app;

-- Auditor (read-only)
CREATE USER geo_auditor IDENTIFIED BY "&auditor_pass" 
  DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_readonly TO geo_auditor;

-- Chief (full access to anonymous data)
CREATE USER geo_chief IDENTIFIED BY "&chief_pass" 
  DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_chief TO geo_chief;
