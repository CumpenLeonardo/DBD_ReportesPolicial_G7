-- =============================================================================
-- 02_pkg_db_installer.sql | Ejecutar como GEO_OWNER
-- PKG_DB_INSTALLER: permite reinstalar desde cero. Elimina todos los objetos del
-- esquema excepto a sí mismo.
-- =============================================================================
CREATE OR REPLACE PACKAGE pkg_db_installer AS
  PROCEDURE drop_all_objects;
END pkg_db_installer;
/

CREATE OR REPLACE PACKAGE BODY pkg_db_installer AS
  PROCEDURE drop_all_objects IS
  BEGIN
    -- Paquetes y funciones.
    FOR r IN (SELECT object_type, object_name FROM user_objects
               WHERE object_type IN ('PACKAGE', 'FUNCTION', 'PROCEDURE')
                 AND object_name <> 'PKG_DB_INSTALLER') LOOP
      EXECUTE IMMEDIATE 'DROP ' || r.object_type || ' ' || r.object_name;
    END LOOP;

    -- Tablas. CASCADE CONSTRAINTS quita las FK, así que el orden no importa.
    FOR r IN (SELECT table_name FROM user_tables
               WHERE table_name LIKE 'TB\_%' ESCAPE '\') LOOP
      EXECUTE IMMEDIATE 'DROP TABLE ' || r.table_name || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;

    -- Secuencias.
    FOR r IN (SELECT sequence_name FROM user_sequences) LOOP
      EXECUTE IMMEDIATE 'DROP SEQUENCE ' || r.sequence_name;
    END LOOP;

    -- DROP TABLE no borra la metadata espacial: se limpia aparte.
    DELETE FROM user_sdo_geom_metadata;
    COMMIT;
  END drop_all_objects;
END pkg_db_installer;
/
