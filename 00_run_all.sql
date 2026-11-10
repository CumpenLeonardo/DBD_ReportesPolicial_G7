-- =============================================================================
-- 00_run_all.sql | Master script: rebuilds the database from scratch
-- Usage (from the scripts folder, in a terminal): sqlplus /nolog @00_run_all.sql
-- Everything that happens is saved in install_log.txt.
--
--   01_security_setup.sql   tablespace, roles and users (as SYS)
--   02_pkg_db_installer.sql installer that cleans the schema
--   10_schema.sql           tables, constraints, indexes, sequences and triggers
--   20_packages.sql         packages pkg_org_mgmt, pkg_cpl_mgmt and pkg_inv_mgmt
--   30_data.sql             test data (runs after the packages because it uses them)
--   40_grants_roles.sql     role permissions and reporters view
--   50_tests.sql            automated tests (they ROLLBACK)
--   99_verify.sql           final check
-- =============================================================================
SET DEFINE ON            -- in case an earlier load in this session disabled it
SET SQLBLANKLINES ON     -- required: several scripts have blank lines inside a CREATE
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
SET LINESIZE 200
SET PAGESIZE 100
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

ACCEPT service    CHAR PROMPT 'Service (e.g. localhost:1521/XEPDB1): '
ACCEPT sys_pass   CHAR PROMPT 'SYS password: ' HIDE
ACCEPT owner_pass CHAR PROMPT 'Password for GEO_OWNER: ' HIDE

SPOOL install_log.txt

-- As administrator: tablespace, roles and users.
CONNECT sys/&sys_pass@&service AS SYSDBA
@@01_security_setup.sql

-- As schema owner: clean up any previous installation and create everything.
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
