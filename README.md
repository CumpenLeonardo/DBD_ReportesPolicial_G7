# DBD_ReportesPolicial_G7
# Modulo INV - Investigacion, Asignacion y Operativos (GEO-DENUNCIA, Grupo 07)

Autor: John Fernando Julca Tarazona

## Archivos y orden de ejecucion

| Orden | Archivo | Contenido |
|---|---|---|
| 1 | `03_inv_ddl.sql` | Limpieza + 6 tablas, restricciones e indices (incluye el indice unico por funcion) |
| 2 | `04_inv_triggers.sql` | Limite N de casos activos, contador `active_case_count`, historial inmutable |
| 3 | `06_pkg_inv_mgmt.sql` | Paquete `PKG_INV_MGMT` (CRUD, `change_status`, `assign_investigator`, `register_operation`) |
| 4 | `05b_inv_data.sql` | Parametro N, asignaciones, historial coherente, equipo de apoyo, operativos |
| 5 | `07_inv_tests.sql` | 21 pruebas con resultado PASS/FAIL (hace ROLLBACK al final) |
| aparte | `05a_com_data_juntas_canales.sql` | Juntas vecinales y canales. **Va ANTES de `05_cpl_data.sql` de Andy** |

## Orden global entre modulos

1. Leonardo: `TB_CFG_*`, `TB_TERR_SECTOR`, `TB_STAFF_OFFICER` (DDL y datos).
2. John: DDL de `TB_COM_NEIGHBORHOOD_ASSOC` y `TB_COM_CHANNEL`, luego `05a_com_data_juntas_canales.sql`.
3. Andy: `03_cpl_ddl.sql`, `04_cpl_triggers.sql`, `05_cpl_data.sql`, `06_pkg_cpl_mgmt.sql`.
4. John: `03_inv_ddl.sql`, `04_inv_triggers.sql`, `06_pkg_inv_mgmt.sql`, `05b_inv_data.sql`, `07_inv_tests.sql`.

## Dependencias de columnas (confirmar con el DDL de los demas)

- `TB_CPL_COMPLAINT`: `complaint_id`, `sector_id`, `current_status`, `registration_date`
- `TB_STAFF_OFFICER`: `officer_cip`, `active_case_count`
- `TB_TERR_SECTOR`: `sector_id`, `sector_name`
- `TB_CFG_PARAMETER`: `param_name`, `param_value`, `description`
- `TB_COM_NEIGHBORHOOD_ASSOC`: `assoc_id`, `sector_id`, `assoc_name`
- `TB_COM_CHANNEL`: `channel_id`, `assoc_id`, `channel_type`

## Decisiones de diseno

- 7 estados: REGISTRADO, VALIDADO_COMISARIA, EN_INVESTIGACION, INTERVENCION_PROGRAMADA, DERIVADO_FISCALIA, ARCHIVADO, RESUELTO.
- ARCHIVADO y RESUELTO son terminales y liberan el cupo del investigador.
- `change_reason` cumple el rol de "observaciones": obligatorio, minimo 10 caracteres.
- El limite N se lee de `TB_CFG_PARAMETER` (`MAX_ACTIVE_CASES`, 15 por defecto).
