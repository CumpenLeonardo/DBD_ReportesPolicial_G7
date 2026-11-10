-- =============================================================================
-- 02_pkg_db_installer.sql | Run as GEO_OWNER
-- PKG_DB_INSTALLER: allows reinstalling from scratch. Drops every object in the
-- schema except itself.
-- =============================================================================
CREATE OR REPLACE PACKAGE pkg_db_installer AS
  PROCEDURE drop_all_objects;
END pkg_db_installer;
/

CREATE OR REPLACE PACKAGE BODY pkg_db_installer AS
  PROCEDURE drop_all_objects IS
  BEGIN
    -- Packages, functions and views.
    FOR r IN (SELECT object_type, object_name FROM user_objects
               WHERE object_type IN ('PACKAGE', 'FUNCTION', 'PROCEDURE', 'VIEW')
                 AND object_name <> 'PKG_DB_INSTALLER') LOOP
      EXECUTE IMMEDIATE 'DROP ' || r.object_type || ' ' || r.object_name;
    END LOOP;

    -- Tables. CASCADE CONSTRAINTS removes the FKs, so the order does not matter.
    FOR r IN (SELECT table_name FROM user_tables
               WHERE table_name LIKE 'TB\_%' ESCAPE '\') LOOP
      EXECUTE IMMEDIATE 'DROP TABLE ' || r.table_name || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;

    -- Secuencias.
    FOR r IN (SELECT sequence_name FROM user_sequences) LOOP
      EXECUTE IMMEDIATE 'DROP SEQUENCE ' || r.sequence_name;
    END LOOP;

    -- DROP TABLE does not delete spatial metadata: it is cleaned separately.
    DELETE FROM user_sdo_geom_metadata;
    COMMIT;
  END drop_all_objects;
END pkg_db_installer;
/