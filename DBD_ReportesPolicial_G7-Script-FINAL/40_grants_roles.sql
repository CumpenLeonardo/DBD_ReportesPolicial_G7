-- =============================================================================
-- 40_grants_roles.sql
-- Role grants on tables and packages, plus views (non-anonymous reporters, tracking, management).
-- Run as GEO_OWNER after the tables and packages exist.
-- Loops over existing tables and packages, so it can be rerun.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Grants by role
--
--   Role               Tables                           Packages
--   role_geo_admin     SELECT, INSERT, UPDATE, DELETE   EXECUTE on all
--   role_geo_chief     SELECT on all                    none
--   role_geo_operator  SELECT, INSERT, UPDATE (*)       EXECUTE except the installer
--   role_geo_readonly  SELECT (*)                       none
--
-- (*) TB_CPL_COMPLAINT_PROTECTION and TB_CPL_REPORTER reveal anonymous reporters' identity,
--     so only role_geo_admin and role_geo_chief see them. Operator and readonly
--     read non-anonymous reporters through VW_CPL_REPORTER_PUBLIC.
--     Anonymous complaint registration works because the package runs with
--     its owner's rights.
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
-- Lists reporters who did not request anonymity: excludes anyone listed in
-- TB_CPL_COMPLAINT_PROTECTION, even if they also filed signed complaints.
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

-- =============================================================================
-- SECTION 3: Tracking and management views
-- =============================================================================

-- -----------------------------------------------------------------------------
-- VW_INV_CASE_TRACKING: dashboard of open complaints (excludes ARCHIVADO and RESUELTO).
-- Shows days in the current status, the PRIMARY investigator and the pending action:
--   POR_VALIDAR      REGISTRADO, not yet validated by the station
--   SIN_INVESTIGADOR validated but no active investigator
--   EN_CURSO         everything else
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_inv_case_tracking AS
SELECT c.complaint_id,
       m.modality_name,
       m.severity_level,
       s.sector_name,
       st.station_name,
       c.current_status,
       NVL(h.last_change, c.registration_date)                                        AS last_status_change,
       TRUNC(SYSDATE) - TRUNC(CAST(NVL(h.last_change, c.registration_date) AS DATE))  AS days_in_status,
       a.officer_cip                                                                  AS investigator_cip,
       o.first_name || ' ' || o.last_name                                             AS investigator_name,
       a.assignment_date,
       (SELECT COUNT(*) FROM tb_ops_operation_complaint oc
         WHERE oc.complaint_id = c.complaint_id)                                      AS linked_operations,
       CASE WHEN c.current_status = 'REGISTRADO' THEN 'POR_VALIDAR'
            WHEN c.current_status IN ('VALIDADO_COMISARIA', 'EN_INVESTIGACION', 'INTERVENCION_PROGRAMADA')
             AND a.assignment_id IS NULL THEN 'SIN_INVESTIGADOR'
            ELSE 'EN_CURSO'
       END                                                                            AS pending_action
  FROM tb_cpl_complaint c
  JOIN tb_cpl_modality  m  ON m.modality_id = c.modality_id
  JOIN tb_terr_sector   s  ON s.sector_id    = c.sector_id
  JOIN tb_org_station   st ON st.station_id  = s.station_id
  LEFT JOIN (SELECT complaint_id, MAX(change_timestamp) AS last_change
               FROM tb_inv_status_history
              GROUP BY complaint_id) h ON h.complaint_id = c.complaint_id
  LEFT JOIN tb_inv_assignment a ON a.complaint_id = c.complaint_id
                               AND a.role_type = 'PRIMARY'
                               AND a.end_date IS NULL
  LEFT JOIN tb_staff_officer o ON o.officer_cip = a.officer_cip
 WHERE c.current_status NOT IN ('ARCHIVADO', 'RESUELTO');

-- -----------------------------------------------------------------------------
-- VW_STAFF_WORKLOAD: one row per officer with rank, station, division and supervisor,
-- and actual workload: open cases as PRIMARY and as support, and operations led.
-- counter_check compares active_case_count with open assignments and flags
-- DESCUADRADO on mismatch.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_staff_workload AS
SELECT o.officer_cip,
       o.first_name || ' ' || o.last_name   AS officer_name,
       rk.rank_name,
       rk.hierarchy_level,
       o.specialty,
       st.station_name,
       d.division_name,
       o.supervisor_cip,
       sup.first_name || ' ' || sup.last_name AS supervisor_name,
       o.active_case_count                  AS stored_case_count,
       NVL(a.primary_cases, 0)              AS open_primary_cases,
       NVL(a.support_cases, 0)              AS open_support_cases,
       NVL(l.pending_operations, 0)         AS pending_operations_led,
       CASE WHEN o.active_case_count = NVL(a.open_cases, 0) THEN 'OK' ELSE 'DESCUADRADO' END AS counter_check
  FROM tb_staff_officer o
  JOIN tb_staff_rank     rk ON rk.rank_id    = o.rank_id
  JOIN tb_org_station    st ON st.station_id = o.station_id
  JOIN tb_org_division   d  ON d.division_id = st.division_id
  LEFT JOIN tb_staff_officer sup ON sup.officer_cip = o.supervisor_cip
  LEFT JOIN (SELECT officer_cip,
                    COUNT(*)                                          AS open_cases,
                    COUNT(CASE WHEN role_type = 'PRIMARY' THEN 1 END) AS primary_cases,
                    COUNT(CASE WHEN role_type = 'SUPPORT' THEN 1 END) AS support_cases
               FROM tb_inv_assignment
              WHERE end_date IS NULL
              GROUP BY officer_cip) a ON a.officer_cip = o.officer_cip
  LEFT JOIN (SELECT leader_cip, COUNT(*) AS pending_operations
               FROM tb_ops_operation
              WHERE operation_status IN ('PROGRAMADO', 'EN EJECUCION', 'RETRASADO')
              GROUP BY leader_cip) l ON l.leader_cip = o.officer_cip;

-- -----------------------------------------------------------------------------
-- VW_TERR_SECTOR_SITUATION: per-sector status (including sectors without complaints).
-- Combines complaints, operations and boards to show where police presence is lacking.
-- open_without_operation counts open complaints not linked to any active operation
-- (CANCELADO does not count as coverage).
-- Joined once to a DISTINCT list of covered complaints (no correlated subquery).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_terr_sector_situation AS
SELECT s.sector_id,
       s.sector_name,
       st.station_name,
       d.division_name,
       NVL(asn.associations, 0)             AS neighborhood_associations,
       NVL(cp.total_complaints, 0)          AS total_complaints,
       NVL(cp.open_complaints, 0)           AS open_complaints,
       NVL(cp.open_without_operation, 0)    AS open_without_operation,
       op.last_executed_operation,
       op.next_scheduled_operation
  FROM tb_terr_sector s
  JOIN tb_org_station  st ON st.station_id  = s.station_id
  JOIN tb_org_division d  ON d.division_id  = st.division_id
  LEFT JOIN (SELECT sector_id, COUNT(*) AS associations
               FROM tb_com_neighborhood_assoc
              GROUP BY sector_id) asn ON asn.sector_id = s.sector_id
  LEFT JOIN (SELECT c.sector_id,
                    COUNT(*) AS total_complaints,
                    COUNT(CASE WHEN c.current_status NOT IN ('ARCHIVADO', 'RESUELTO') THEN 1 END) AS open_complaints,
                    COUNT(CASE WHEN c.current_status NOT IN ('ARCHIVADO', 'RESUELTO')
                                AND cov.complaint_id IS NULL THEN 1 END)                          AS open_without_operation
               FROM tb_cpl_complaint c
               LEFT JOIN (SELECT DISTINCT oc.complaint_id
                            FROM tb_ops_operation_complaint oc
                            JOIN tb_ops_operation o ON o.operation_id = oc.operation_id
                           WHERE o.operation_status <> 'CANCELADO') cov ON cov.complaint_id = c.complaint_id
              GROUP BY c.sector_id) cp ON cp.sector_id = s.sector_id
  LEFT JOIN (SELECT sector_id,
                    MAX(CASE WHEN operation_status = 'EJECUTADO'  THEN operation_date END) AS last_executed_operation,
                    MIN(CASE WHEN operation_status = 'PROGRAMADO' THEN operation_date END) AS next_scheduled_operation
               FROM tb_ops_operation
              GROUP BY sector_id) op ON op.sector_id = s.sector_id;


-- All roles can query these views (read-only).
GRANT SELECT ON vw_inv_case_tracking TO role_geo_admin;
GRANT SELECT ON vw_inv_case_tracking TO role_geo_chief;
GRANT SELECT ON vw_inv_case_tracking TO role_geo_operator;
GRANT SELECT ON vw_inv_case_tracking TO role_geo_readonly;

GRANT SELECT ON vw_staff_workload TO role_geo_admin;
GRANT SELECT ON vw_staff_workload TO role_geo_chief;
GRANT SELECT ON vw_staff_workload TO role_geo_operator;
GRANT SELECT ON vw_staff_workload TO role_geo_readonly;

GRANT SELECT ON vw_terr_sector_situation TO role_geo_admin;
GRANT SELECT ON vw_terr_sector_situation TO role_geo_chief;
GRANT SELECT ON vw_terr_sector_situation TO role_geo_operator;
GRANT SELECT ON vw_terr_sector_situation TO role_geo_readonly;
