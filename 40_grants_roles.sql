-- =============================================================================
-- 40_grants_roles.sql
-- Role permissions on tables and packages, and view of non-anonymous reporters.
-- Run as GEO_OWNER once the tables and packages exist.
-- Goes through the existing tables and packages, so it can be run again.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Permissions per role
--
--   Role               Tables                           Packages
--   role_geo_admin     SELECT, INSERT, UPDATE, DELETE   EXECUTE on all
--   role_geo_chief     SELECT on all                    none
--   role_geo_operator  SELECT, INSERT, UPDATE (*)       EXECUTE except the installer
--   role_geo_readonly  SELECT (*)                       none
--
-- (*) TB_CPL_COMPLAINT_PROTECTION and TB_CPL_REPORTER reveal the identity of anonymous
--     reporters and are only visible to role_geo_admin and role_geo_chief. The operator and the query role
--     read non-anonymous reporters through the VW_CPL_REPORTER_PUBLIC view.
--     Anonymous complaint registration works because the package runs with the
--     rights of its owner.
-- =============================================================================
BEGIN
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name LIKE 'TB\_%' ESCAPE '\') LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ' || t.table_name || ' TO role_geo_admin';
    EXECUTE IMMEDIATE 'GRANT SELECT ON ' || t.table_name || ' TO role_geo_chief';
    IF t.table_name NOT IN ('TB_CPL_COMPLAINT_PROTECTION', 'TB_CPL_REPORTER') THEN
      EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE ON ' || t.table_name || ' TO role_geo_operator';
      EXECUTE IMMEDIATE 'GRANT SELECT ON ' || t.table_name || ' TO role_geo_readonly';
    END IF;
  END LOOP;

  FOR p IN (SELECT object_name FROM user_objects WHERE object_type = 'PACKAGE') LOOP
    EXECUTE IMMEDIATE 'GRANT EXECUTE ON ' || p.object_name || ' TO role_geo_admin';
    IF p.object_name <> 'PKG_DB_INSTALLER' THEN
      EXECUTE IMMEDIATE 'GRANT EXECUTE ON ' || p.object_name || ' TO role_geo_operator';
    END IF;
  END LOOP;
END;
/

-- =============================================================================
-- SECTION 2: View VW_CPL_REPORTER_PUBLIC
-- Lists the reporters who did not request anonymity: excludes any reporter listed
-- in TB_CPL_COMPLAINT_PROTECTION, even if they filed other signed complaints.
-- =============================================================================
CREATE OR REPLACE VIEW vw_cpl_reporter_public AS
SELECT r.*
  FROM tb_cpl_reporter r
 WHERE NOT EXISTS (SELECT 1
                     FROM tb_cpl_complaint_protection p
                    WHERE p.id_reporter = r.id_reporter);

-- All roles can query the view (read-only).
GRANT SELECT ON vw_cpl_reporter_public TO role_geo_admin;
GRANT SELECT ON vw_cpl_reporter_public TO role_geo_chief;
GRANT SELECT ON vw_cpl_reporter_public TO role_geo_operator;
GRANT SELECT ON vw_cpl_reporter_public TO role_geo_readonly;
