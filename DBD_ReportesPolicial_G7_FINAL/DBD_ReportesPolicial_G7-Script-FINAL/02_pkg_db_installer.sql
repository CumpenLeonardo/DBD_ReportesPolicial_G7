-- =============================================================================
-- 02_pkg_db_installer.sql | Run as GEO_OWNER
-- PKG_DB_INSTALLER: drops every schema object except itself,
-- so the install can be rerun from scratch.
-- =============================================================================
CREATE OR REPLACE PACKAGE pkg_db_installer AS
  PROCEDURE drop_all_objects;
END pkg_db_installer;
/

CREATE OR REPLACE PACKAGE BODY pkg_db_installer AS
  PROCEDURE drop_all_objects IS
  BEGIN
    -- Packages, functions, procedures, views.
    FOR r IN (SELECT object_type, object_name FROM user_objects
               WHERE object_type IN ('PACKAGE', 'FUNCTION', 'PROCEDURE', 'VIEW')
                 AND object_name <> 'PKG_DB_INSTALLER') LOOP
      EXECUTE IMMEDIATE 'DROP ' || r.object_type || ' ' || r.object_name;
    END LOOP;

    -- Tables (CASCADE CONSTRAINTS makes the order irrelevant).
    FOR r IN (SELECT table_name FROM user_tables
               WHERE table_name LIKE 'TB\_%' ESCAPE '\') LOOP
      EXECUTE IMMEDIATE 'DROP TABLE ' || r.table_name || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;

    -- Sequences.
    FOR r IN (SELECT sequence_name FROM user_sequences) LOOP
      EXECUTE IMMEDIATE 'DROP SEQUENCE ' || r.sequence_name;
    END LOOP;

    -- Spatial metadata is not removed by DROP TABLE.
    DELETE FROM user_sdo_geom_metadata;
    COMMIT;
  END drop_all_objects;
END pkg_db_installer;
/