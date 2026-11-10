-- =============================================================================
-- 01_security_setup.sql | Execute connected as SYSDBA
-- =============================================================================

ACCEPT app_pass     CHAR PROMPT 'Password for GEO_APP: ' HIDE
ACCEPT auditor_pass CHAR PROMPT 'Password for GEO_AUDITOR: ' HIDE
ACCEPT chief_pass   CHAR PROMPT 'Password for GEO_CHIEF: ' HIDE

-- =============================================================================
-- 1. PREVENTIVE AND IDEMPOTENT CLEANUP (Guarantees clean re-installation)
-- =============================================================================
SET SERVEROUTPUT ON;

BEGIN
  DBMS_OUTPUT.PUT_LINE('-> Terminating existing sessions, users, roles, and tablespace...');

  -- 1.1 Disconnect concurrent active sessions to prevent ORA-01940
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

  -- 1.2 Drop schema users
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

  -- 1.3 Drop security roles
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

  -- 1.4 Drop tablespace including datafiles and constraints
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
-- 2. AGNOSTIC TABLESPACE ALLOCATION (OMF / RELATIVE PATH)
-- =============================================================================
DECLARE
  v_omf VARCHAR2(512);
BEGIN
  -- Check if Oracle Managed Files (OMF) is enabled in the database container
  BEGIN
    SELECT value INTO v_omf 
    FROM v$parameter 
    WHERE name = 'db_create_file_dest';
  EXCEPTION 
    WHEN OTHERS THEN v_omf := NULL;
  END;

  IF v_omf IS NOT NULL THEN
    -- Native OMF syntax: handles paths and filenames automatically
    EXECUTE IMMEDIATE 'CREATE TABLESPACE ts_geo_data DATAFILE SIZE 200M AUTOEXTEND ON NEXT 50M MAXSIZE 2G';
  ELSE
    -- Standard relative filename syntax: created inside PDB default folder
    EXECUTE IMMEDIATE 'CREATE TABLESPACE ts_geo_data DATAFILE ''ts_geo_data01.dbf'' SIZE 200M AUTOEXTEND ON NEXT 50M MAXSIZE 2G';
  END IF;

  DBMS_OUTPUT.PUT_LINE('-> Tablespace TS_GEO_DATA created successfully.');
END;
/

-- =============================================================================
-- 3. ROLE CREATION AND SESSION PRIVILEGES
-- =============================================================================
CREATE ROLE role_geo_admin;
CREATE ROLE role_geo_operator;
CREATE ROLE role_geo_readonly;
CREATE ROLE role_geo_chief;

GRANT CREATE SESSION TO role_geo_admin, role_geo_operator, role_geo_readonly, role_geo_chief;

-- =============================================================================
-- 4. SYSTEM USERS AND QUOTA ASSIGNMENT
-- =============================================================================

-- Schema Owner: GEO_OWNER
CREATE USER geo_owner IDENTIFIED BY "&owner_pass"
  DEFAULT TABLESPACE ts_geo_data 
  QUOTA UNLIMITED ON ts_geo_data;

GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE PROCEDURE, 
      CREATE TRIGGER, CREATE VIEW TO geo_owner;

-- Application User: GEO_APP (Java Client)
CREATE USER geo_app IDENTIFIED BY "&app_pass" 
  DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_operator TO geo_app;

-- Audit / Readonly User: GEO_AUDITOR
CREATE USER geo_auditor IDENTIFIED BY "&auditor_pass" 
  DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_readonly TO geo_auditor;

-- High Ranking Officer: GEO_CHIEF (Full access to anonymous data)
CREATE USER geo_chief IDENTIFIED BY "&chief_pass" 
  DEFAULT TABLESPACE ts_geo_data;
GRANT role_geo_chief TO geo_chief;
