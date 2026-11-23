# Estabilidad y competitividad electoral en las provincias argentinas

Trabajo práctico final de **Ciencia de Datos** (FCE-UBA, 2.º cuatrimestre 2026) · **Grupo 07**

## Integrantes

- Gian Franco Pugliares (899778)
- Ezequiel Richard Serrudo Triveño (917960)
- Maximo Casella (916038)

## Objetivo e hipótesis

Analizamos si el voto presidencial de los territorios argentinos se mantuvo entre las elecciones generales de 2019 y 2023 (primera vuelta).

**Hipótesis:** el alineamiento electoral de los territorios es persistente. Departamentos y provincias tienden a mantener su perfil de voto entre 2019 y 2023, aunque la irrupción de La Libertad Avanza reordena parte de ese patrón.

Preguntas de trabajo:

1. ¿El espacio que ganó en cada departamento en 2023 es independiente del que había ganado en 2019? → **test Chi cuadrado**
2. ¿Qué provincias se parecen entre sí en su perfil de votos de 2019 y 2023? → **clustering k-means + PCA**
3. ¿La Libertad Avanza sacó más votos en 2023 donde JxC era más fuerte en 2019? → **regresión lineal**

## Datos

| Base | Fuente | Período | Unidad de observación |
|---|---|---|---|
| Resultados presidenciales por provincia 1983-2019 | Escrutinios definitivos de la DINE, compilados por [electorAr](https://github.com/PoliticaArgentina/data_warehouse) | 2019 (se usa solo esta elección) | Provincia × lista |
| Resultados presidenciales 2023 | Escrutinio provisorio de la [DINE](https://www.argentina.gob.ar/dine/resultados-electorales), por mesa, resumido a provincia | 2023 | Provincia × lista |
| Resultados por departamento 2019 y 2023 (`raw/departamentos_2019_2023.csv`) | Escrutinio provisorio de la [DINE](https://www.argentina.gob.ar/dine/resultados-electorales) por mesa, agregado a departamento con las mesas escrutadas | 2019 y 2023 | Departamento (527 comparables entre años) |

**Base auxiliar:** `auxiliar/espacios_2019_2023.csv` asigna cada lista a uno de los 5 espacios del análisis (Peronismo, JxC, Derecha liberal, Tercera vía, Izquierda), con una nota que justifica los casos dudosos (Unite + NOS como antecedente de la derecha liberal; Lavagna y Schiaretti como Tercera vía). Se une a la base por año y nombre de lista; el script 01 verifica que no quede ninguna lista sin espacio, así que el cruce no pierde observaciones.

Todos los porcentajes se calculan sobre **votos positivos** (sin blancos ni nulos).

### Variables utilizadas

| Variable | Descripción | Tipo | Faltantes |
|---|---|---|---|
| `anio` | Año de la elección (2019 o 2023) | Numérica | 0 |
| `provincia` | Distrito electoral (24: 23 provincias y CABA) | Categórica | 0 |
| `espacio` | Espacio político: Peronismo, JxC, Derecha liberal, Tercera vía, Izquierda | Categórica | 0 |
| `votos` | Votos positivos del espacio en la provincia | Numérica (votos) | 0 |
| `pct` | Votos del espacio / votos positivos de la provincia × 100 | Numérica (%) | 0 |
| `electores` | Electores habilitados | Numérica (personas) | 0 |
| `participacion` | Votos emitidos / electores × 100 | Numérica (%) | 0 |
| `pct_blancos`, `pct_nulos` | Votos en blanco o nulos / votos emitidos × 100 | Numérica (%) | 0 |
| `peronismo_2019` … `izquierda_2023` | `pct` de cada espacio en cada año, en formato ancho (10 variables del clustering) | Numérica (%) | 0 |

## Estructura del repositorio

```
tp_elecciones/
├── raw/            # Datos crudos, tal como se descargaron (no se modifican)
├── auxiliar/       # Clasificación de listas en espacios
├── input/          # Bases procesadas que generan los scripts
├── output/
│   ├── tablas/     # Tablas de resultados (.csv)
│   └── graficos/   # Gráficos (.jpg, 300 dpi)
├── script/         # Scripts numerados en orden de ejecución
├── utils/          # Funciones propias (una por archivo)
├── tp_elecciones.Rproj
└── README.md
```

## Cómo reproducir el análisis

1. Descargar o clonar el repositorio y abrir **`tp_elecciones.Rproj`** con RStudio (así todas las rutas son relativas a la carpeta del proyecto).
2. Instalar una sola vez los paquetes necesarios (probado con R 4.2 o superior y ggrepel 0.9 o superior):

   ```r
   install.packages(c("tidyverse", "scales", "ggrepel", "cluster", "patchwork", "lmtest", "sandwich"))
   ```

3. Correr los scripts de `script/` **en orden**. Cada uno lee los archivos que guardó el anterior, así que se pueden correr en sesiones distintas.

| Script | Qué hace | Lee | Genera |
|---|---|---|---|
| `00a_descarga_1983_2019.R` | **Opcional.** Descarga los resultados 1983-2019 de electorAr (necesita internet) | internet | `raw/presi_1983_2019.csv` |
| `00b_resumen_mesas_2023.R` | **Opcional.** Resume el archivo de la DINE 2023 por mesa (1 GB, no está en el repo) a nivel provincia | `raw/2023_crudo/` | `raw/presi_2023.csv` |
| `01_limpieza_base_provincial.R` | Une 2019 y 2023, limpia los nombres de las listas, asigna espacios y calcula el % de cada espacio y los totales por provincia | `raw/`, `auxiliar/` | `input/provincias_espacios.csv`, `input/provincias_totales.csv` |
| `02_descriptivas.R` | Estadísticas descriptivas por espacio y año, participación, blancos y nulos | `input/` | `output/tablas/02_*.csv`, `output/graficos/02_distribucion_espacios.jpg` |
| `03_faltantes_outliers.R` | Diagnóstico de faltantes, outliers por z-score (\|z\| > 2,5), decisión y descriptivas con y sin atípicos | `raw/`, `input/` | `output/tablas/03_*.csv`, `output/graficos/03_outliers_zscore.jpg`, `input/provincias_matriz.csv`, `input/provincias_atipicas.csv` |
| `04_chi_cuadrado_departamentos.R` | Ganador de cada departamento en 2019 y 2023, test Chi cuadrado de independencia (con Fisher si hay esperadas < 5), V de Cramér, residuos y % que repitió ganador | `raw/departamentos_2019_2023.csv` | `input/departamentos_ganador.csv`, `output/tablas/04_*.csv`, `output/graficos/04_chi_cuadrado_transiciones.jpg` |
| `05_clustering_pca.R` | Elección de k (codo y silueta), k-means con k = 3, robustez (Ward y sin atípicos) y PCA. Genera el gráfico exploratorio de la instancia 3 | `input/provincias_matriz.csv`, `input/provincias_atipicas.csv` | `output/tablas/05_*.csv`, `output/graficos/05_*.jpg`, `input/provincias_grupos.csv` |
| `06_regresion_lla.R` | Regresión lineal del % de LLA 2023 según el % de JxC 2019 (y según el grupo del clustering), supuestos (Shapiro-Wilk, Breusch-Pagan, distancia de Cook), errores robustos y robustez sin provincias influyentes | `input/provincias_matriz.csv`, `input/provincias_grupos.csv` | `output/tablas/06_*.csv`, `output/graficos/06_regresion_lla_jxc.jpg` |
| `07_grafico_comunicativo.R` | Gráfico comunicativo (instancia 3, corregido): si el espacio que ganó cada provincia en 2019 la retuvo en 2023, con el % de votos en ambos años | `input/provincias_espacios.csv` | `output/tablas/07_retencion_provincias.csv`, `output/graficos/07_comunicativo_retencion.jpg` |

Los scripts `00a` y `00b` no hace falta correrlos: sus resultados ya están en `raw/`.

### Funciones propias (`utils/`)

| Archivo | Función | Para qué | Se usa en |
|---|---|---|---|
| `limpiar_nombre_lista.R` | `limpiar_nombre_lista()` | Unifica cómo está escrito el nombre de cada lista | 01 |
| `nombre_variable.R` | `nombre_variable()` | Arma el nombre interno de una variable (`tercera_via_2019`) | 03 |
| `etiqueta_variable.R` | `etiqueta_variable()` | Traduce el nombre interno al texto de los gráficos (`Tercera vía 2019`) | 03, 05 |
| `tema_tp.R` | `tema_tp()` | Tema de ggplot común a todos los gráficos | 02 a 07 |
| `fuente_tp.R` | `fuente_tp()` | Nota de fuente al pie de los gráficos provinciales | 02, 03, 05, 06, 07 |
| `guardar_grafico.R` | `guardar_grafico()` | Exporta con `ggsave()` a JPG, 300 dpi, 22 cm de ancho | 02 a 07 |

## Análisis realizado

1. **Limpieza y descriptivas.** 24 provincias × 2 elecciones × 5 espacios. No hay valores faltantes en las variables usadas.
2. **Outliers.** Valores atípicos (\|z\| > 2,5) en 4 provincias: Córdoba (Tercera vía 2023 y JxC 2019), Santiago del Estero, CABA y Salta. Son resultados genuinos, no errores de carga, por lo que se mantienen; las descriptivas con y sin ellos cambian poco.
3. **Chi cuadrado (departamentos).** El ganador de 2023 no es independiente del de 2019: χ² = 214,4, gl = 3, p < 0,001, V de Cramér = 0,64 (n = 527). El 66 % de los departamentos repitió ganador, contra 47 % esperado si fueran independientes. Pero la persistencia es asimétrica: el peronismo retuvo el 79 % de sus departamentos y JxC el 32 % (el 51 % lo ganó LLA).
4. **Clustering + PCA (provincias).** k-means con k = 3 (50 inicios, variables estandarizadas): *Mayor caída del peronismo* (5), *Bicoalición en 2019* (11) y *Peronismo persistente* (8). Explican el 44,3 % de la varianza; silueta media 0,25 (estructura débil). Ward coincide en 23 de 24 provincias.
5. **Regresión (provincias).** El % de LLA en 2023 no se relaciona con el % de JxC en 2019: pendiente 0,06 (IC 95 %: −0,28 a 0,40), p = 0,70, R² = 0,01. El resultado se mantiene al controlar por grupo y al sacar las provincias influyentes (CABA y Santiago del Estero). Se cumplen normalidad (Shapiro p = 0,63) y homocedasticidad (Breusch-Pagan p = 0,22); se reportan errores robustos.

## Conclusiones principales

- **La hipótesis de persistencia se confirma solo en parte.** Hay asociación fuerte entre el ganador de 2019 y el de 2023, pero la persistencia se da en el peronismo y no en el no peronismo: el peronismo retuvo 12 de sus 18 provincias y el 79 % de sus departamentos; JxC, 1 de 6 provincias y el 32 % de sus departamentos.
- **La Libertad Avanza no creció más donde JxC era fuerte.** Su voto fue parejo entre provincias (entre 20 % y 43 %) e independiente de la fuerza previa de JxC. JxC perdió sus territorios porque su voto cayó en todas partes, no porque LLA fuera más fuerte justamente ahí.
- Los resultados son asociaciones con datos agregados: no permiten saber qué hicieron los votantes individuales (no hay "flujos" observables) ni establecer causalidad.

## Próximos pasos

- Estimar transferencias de votos con métodos de inferencia ecológica a nivel mesa.
- Repetir la regresión a nivel departamento (527 casos) para ganar potencia.
- Sumar el balotaje 2023 y elecciones anteriores (2015) para ver si la persistencia peronista es estable en el tiempo.
