## Sistema de Gestión y Georreferenciación de Denuncias Policiales (Grupo 7)

Repositorio con los scripts en Oracle Database (SQL, PL/SQL y soporte espacial `SDO_GEOMETRY`) para la **Entrega Parcial 2** del curso de Administración de Base de Datos.

---

## ¿Por qué dividimos los scripts en varios archivos?

Sabemos que la idea de pedir un único archivo `.sql` es que usted pueda levantar toda la base de datos de golpe en su computadora, sin tener que ejecutar scripts sueltos ni preocuparse por el orden de dependencias.

Sin embargo, conforme fuimos avanzando con el proyecto, vimos que juntar todo (18 tablas, 4 paquetes PL/SQL, 7 triggers, 4 vistas, la carga de 80 denuncias y 64 pruebas) en un solo archivo iba a superar las 2,500 líneas. Hacerlo así se volvía muy pesado para revisar, depurar y trabajar entre nosotros. Por eso preferimos ordenarlo en **9 scripts numerados (`00` al `99`)**, manteniendo la instalación en un solo paso:

1. **Separación de sesiones (`SYSDBA` vs. `GEO_OWNER`):** En Oracle, la creación de tablespaces, roles y usuarios tiene que hacerse como `SYSDBA`, mientras que todas las tablas, paquetes y triggers deben quedar dentro del esquema `GEO_OWNER`. Separarlos evita mezclar permisos de administrador con los objetos del negocio.
2. **Trabajo en equipo y mantenimiento:** Dividir el código por capas (seguridad, estructura, paquetes, datos, permisos y pruebas) nos permitió avanzar en paralelo por GitHub sin pisarnos el trabajo, y corregir errores puntuales sin tener que volver a correr todo desde cero cada vez.
3. **Instalación en un solo comando (`00_run_all.sql`):** Para no perder la comodidad de un archivo único, preparamos el script maestro `00_run_all.sql`. Basta con ejecutar ese único archivo en consola para que Oracle conecte las sesiones necesarias y corra todos los demás scripts en orden automáticamente.

---

## Contenido de la carpeta de scripts

Los archivos están numerados según el orden en que se ejecutan:

| Archivo | Qué hace | Usuario |
| :--- | :--- | :---: |
| **`00_run_all.sql`** | **Script maestro.** Ejecuta toda la instalación en cascada y guarda la salida en `install_log.txt`. | `SYSDBA` -> `GEO_OWNER` |
| **`01_security_setup.sql`** | Crea el tablespace `TS_GEO_DATA` (compatible con OMF/Docker y `REUSE`), los 4 roles y los 4 usuarios. | `SYS AS SYSDBA` |
| **`02_pkg_db_installer.sql`** | Crea el paquete `PKG_DB_INSTALLER` para limpiar objetos previos si se quiere reinstalar desde cero. | `GEO_OWNER` |
| **`10_schema.sql`** | Crea las 18 tablas, constraints, índices B-Tree, índices espaciales R-Tree, 16 secuencias y 7 triggers. | `GEO_OWNER` |
| **`20_packages.sql`** | Compila los 3 paquetes de negocio: `PKG_ORG_MGMT`, `PKG_CPL_MGMT` y `PKG_INV_MGMT`. | `GEO_OWNER` |
| **`30_data.sql`** | Inserta datos base (monedas, divisiones, comisarías, 6 sectores con polígonos, 10 oficiales, canales y juntas), 80 denuncias y transiciones de investigación/operativos. | `GEO_OWNER` |
| **`40_grants_roles.sql`** | Crea las 4 vistas (`VW_CPL_REPORTER_PUBLIC`, `VW_INV_CASE_TRACKING`, `VW_STAFF_WORKLOAD`, `VW_TERR_SECTOR_SITUATION`) y asigna permisos a los roles. | `GEO_OWNER` |
| **`50_tests.sql`** | Corre las **64 pruebas unitarias** del sistema (termina con `ROLLBACK` para dejar intactos los datos cargados). | `GEO_OWNER` |
| **`99_verify.sql`** | Revisa que no haya objetos inválidos, cuenta las filas de las 18 tablas y verifica la consistencia general. | `GEO_OWNER` |

---

## Cómo instalarlo en su computadora

---

### Opción 1: Instalación automática por consola 

1. Descargue el repositorio (`Code > Download ZIP`) y descomprímalo.
2. Abra una terminal (CMD, PowerShell o Bash) y entre a la carpeta donde están los `.sql`:

~~~bash
cd ruta/a/DBD_ReportesPolicial_G7-Script-FINAL
~~~

3. Ejecute el script maestro con SQL\*Plus:

~~~bash
sqlplus /nolog @00_run_all.sql
~~~

4. El script le pedirá ingresar por teclado:
   * **Service:** el servicio de su PDB (por ejemplo: `localhost:1521/FREEPDB1` o `localhost:1521/XEPDB1`).
   * **SYS password:** la contraseña de su usuario `SYS`.
   * **Contraseñas de los usuarios del proyecto:** la clave que desee asignar a `GEO_OWNER`, `GEO_APP`, `GEO_CHIEF` y `GEO_AUDITOR`.

En unos 10–15 segundos terminará todo el despliegue y quedará el registro completo en **`install_log.txt`** dentro de la misma carpeta.

---

### Opción 2: Ejecución paso a paso desde SQL Developer

Si prefiere correrlo desde **Oracle SQL Developer**:

1. Conéctese como **`SYS` (Rol: `SYSDBA`)**, abra **`01_security_setup.sql`** y ejecútelo con **`F5`** (ingresando las contraseñas en las ventanas que vayan saliendo).
2. Cree una conexión nueva para **`GEO_OWNER`** (con la clave que le puso en el paso anterior y el mismo servicio PDB).
3. Conectado como **`GEO_OWNER`**, abra y ejecute con **`F5`** cada archivo en orden:
   * `02_pkg_db_installer.sql` *(opcional: si ya había instalado antes, ejecute `EXEC pkg_db_installer.drop_all_objects;` para limpiar)*
   * `10_schema.sql`
   * `20_packages.sql`
   * `30_data.sql`
   * `40_grants_roles.sql`
   * `50_tests.sql`
   * `99_verify.sql`

---

## Qué esperar al finalizar (`99_verify.sql`)

Si todo salió bien, el resumen final mostrará:
* **Objetos inválidos y errores de compilación:** `0`
* **Objetos creados:** `18` tablas, `16` secuencias (`SEQ_*`), `4` vistas, `4` paquetes y `7` triggers.
* **Pruebas unitarias (`50_tests.sql`):** `64 PASS, 0 FAIL` (23 de Denuncias, 12 de Organización/Territorio, 21 de Investigación/Operativos y 8 de Vistas).
* **Consistencia:** `SECTORES_SIN_POLIGONO = 0`, `CONTADORES_INCORRECTOS = 0` y `DENUNCIAS_SIN_GEOMETRIA = 0`.
