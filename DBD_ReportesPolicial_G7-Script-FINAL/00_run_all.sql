-- =============================================================================
--   00_run_all.sql | Master script: rebuilds the database from scratch
-- Usage: sqlplus /nolog @00_run_all.sql (from the scripts folder)
-- Output is logged to install_log.txt.
--
--   01_security_setup.sql   tablespace, roles, users (as SYS)
--   02_pkg_db_installer.sql schema cleanup package
--   10_schema.sql           tables, constraints, indexes, sequences, triggers
--   20_packages.sql         pkg_org_mgmt, pkg_cpl_mgmt, pkg_inv_mgmt
--   30_data.sql             test data (needs the packages)
--   40_grants_roles.sql     role grants and views
--   50_tests.sql            automated tests (ROLLBACK)
--   99_verify.sql           final checks
-- =============================================================================
SET DEFINE ON            -- enable substitution variables
SET SQLBLANKLINES ON     -- allow blank lines inside CREATE statements
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
SET LINESIZE 200
SET PAGESIZE 100
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

ACCEPT service    CHAR PROMPT 'Service (e.g. localhost:1521/XEPDB1): '
ACCEPT sys_pass   CHAR PROMPT 'SYS password: ' HIDE
ACCEPT owner_pass CHAR PROMPT 'Password for GEO_OWNER: ' HIDE

SPOOL install_log.txt

-- As admin: tablespace, roles, users.
CONNECT sys/&sys_pass@&service AS SYSDBA
@@01_security_setup.sql

-- As schema owner: clean any previous install, then build everything.
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
