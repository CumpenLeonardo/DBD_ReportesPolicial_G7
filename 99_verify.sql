-- =============================================================================
-- 99_verify.sql | Ejecutar como GEO_OWNER
-- Revisión final de la instalación: objetos inválidos, errores de compilación, conteos y consistencia.
-- Cada bloque indica el resultado esperado.
-- =============================================================================
SET PAGESIZE 100
SET LINESIZE 200

PROMPT
PROMPT === 1. Objetos INVALIDOS (esperado: no rows selected) ===
SELECT object_type, object_name FROM user_objects WHERE status <> 'VALID';

PROMPT
PROMPT === 2. Errores de compilación (esperado: no rows selected) ===
SELECT name, type, line, text FROM user_errors ORDER BY name, type, sequence;

PROMPT
PROMPT === 3. Cantidad de objetos por tipo (esperado: 18 TABLE, 4 PACKAGE, 4 PACKAGE BODY, 1 VIEW) ===
SELECT object_type, COUNT(*) AS total
  FROM user_objects
 WHERE object_name NOT LIKE 'MDRT%' AND object_name NOT LIKE 'ISEQ$$%'
 GROUP BY object_type
 ORDER BY object_type;

PROMPT
PROMPT === 4. Filas por tabla (ninguna debe estar en 0) ===
SELECT 'TB_CFG_CURRENCY' AS tabla, COUNT(*) AS filas FROM tb_cfg_currency
UNION ALL SELECT 'TB_ORG_DIVISION',             COUNT(*) FROM tb_org_division
UNION ALL SELECT 'TB_ORG_STATION',              COUNT(*) FROM tb_org_station
UNION ALL SELECT 'TB_TERR_SECTOR',              COUNT(*) FROM tb_terr_sector
UNION ALL SELECT 'TB_STAFF_RANK',               COUNT(*) FROM tb_staff_rank
UNION ALL SELECT 'TB_STAFF_OFFICER',            COUNT(*) FROM tb_staff_officer
UNION ALL SELECT 'TB_COM_CHANNEL',              COUNT(*) FROM tb_com_channel
UNION ALL SELECT 'TB_COM_NEIGHBORHOOD_ASSOC',   COUNT(*) FROM tb_com_neighborhood_assoc
UNION ALL SELECT 'TB_CPL_MODALITY',             COUNT(*) FROM tb_cpl_modality
UNION ALL SELECT 'TB_CPL_ESTABLISHMENT',        COUNT(*) FROM tb_cpl_establishment
UNION ALL SELECT 'TB_CPL_REPORTER',             COUNT(*) FROM tb_cpl_reporter
UNION ALL SELECT 'TB_CPL_COMPLAINT_PROTECTION', COUNT(*) FROM tb_cpl_complaint_protection
UNION ALL SELECT 'TB_CPL_COMPLAINT',            COUNT(*) FROM tb_cpl_complaint
UNION ALL SELECT 'TB_CPL_DIGITAL_EVIDENCE',     COUNT(*) FROM tb_cpl_digital_evidence
UNION ALL SELECT 'TB_INV_ASSIGNMENT',           COUNT(*) FROM tb_inv_assignment
UNION ALL SELECT 'TB_INV_STATUS_HISTORY',       COUNT(*) FROM tb_inv_status_history
UNION ALL SELECT 'TB_OPS_OPERATION',            COUNT(*) FROM tb_ops_operation
UNION ALL SELECT 'TB_OPS_OPERATION_COMPLAINT',  COUNT(*) FROM tb_ops_operation_complaint;


PROMPT
PROMPT === 5. Denuncias por estado (esperado: REGISTRADO 73, VALIDADO 2, EN_INVESTIGACION 2, INTERVENCION 1, DERIVADO 1, ARCHIVADO 1) ===
SELECT current_status, COUNT(*) AS denuncias FROM tb_cpl_complaint GROUP BY current_status ORDER BY 2 DESC;

PROMPT
PROMPT === 6. Consistencia (los tres conteos deben ser 0) ===
SELECT (SELECT COUNT(*) FROM tb_terr_sector WHERE polygon_area IS NULL) AS sectores_sin_poligono,
       (SELECT COUNT(*) FROM tb_staff_officer o
         WHERE o.active_case_count <> (SELECT COUNT(*) FROM tb_inv_assignment a
                                        WHERE a.officer_cip = o.officer_cip AND a.end_date IS NULL)) AS contadores_incorrectos,
       (SELECT COUNT(*) FROM tb_cpl_complaint WHERE incident_location IS NULL) AS denuncias_sin_geometria
  FROM dual;

PROMPT
PROMPT === 7. Roles y permisos (esperado: 4 roles, y GEO_CHIEF/GEO_APP/GEO_AUDITOR con su rol) ===
SELECT table_name, grantee, privilege FROM user_tab_privs
 WHERE table_name IN ('TB_CPL_REPORTER', 'TB_CPL_COMPLAINT_PROTECTION', 'VW_CPL_REPORTER_PUBLIC')
 ORDER BY table_name, grantee, privilege;
