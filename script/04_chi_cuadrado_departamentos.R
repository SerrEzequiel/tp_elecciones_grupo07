# ==============================================================================
# 04_chi_cuadrado_departamentos.R
# Método de inferencia: test Chi cuadrado de independencia entre el espacio que
# ganó cada departamento en 2019 y el que ganó en 2023.
# H0: el ganador de 2023 es independiente del ganador de 2019.
#
# Lee:     raw/departamentos_2019_2023.csv
#          (% de cada espacio por departamento; escrutinio provisorio de la DINE
#          por mesa, resumido a departamento solo con mesas escrutadas)
# Guarda:  input/departamentos_ganador.csv
#          output/tablas/04_departamentos_sin_par.csv
#          output/tablas/04_tabla_contingencia.csv
#          output/tablas/04_chi_cuadrado.csv
#          output/tablas/04_residuos_estandarizados.csv
#          output/graficos/04_chi_cuadrado_transiciones.jpg
# ==============================================================================

library(tidyverse)
library(scales)

source("utils/tema_tp.R")
source("utils/guardar_grafico.R")

departamentos <- read_csv("raw/departamentos_2019_2023.csv", show_col_types = FALSE)

minimo_ganados <- 10   # espacios que ganan menos departamentos se agrupan en "Otros"

# ------------------------------------------------------------------------------
# 1. Ganador de cada departamento en cada elección
# ------------------------------------------------------------------------------

ganador <- departamentos |>
  filter(esp != "Blanco") |>
  group_by(anio, provincia, departamento, distrito_id, seccion_id) |>
  slice_max(pct, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(anio, provincia, departamento, distrito_id, seccion_id, ganador = esp)

count(ganador, anio)

# ------------------------------------------------------------------------------
# 2. Pares 2019-2023: departamentos sin dato en alguno de los dos años
# ------------------------------------------------------------------------------

pares <- ganador |>
  select(anio, provincia, departamento, distrito_id, seccion_id, ganador) |>
  pivot_wider(names_from = anio, values_from = ganador, names_prefix = "ganador_")

sin_par <- filter(pares, is.na(ganador_2019) | is.na(ganador_2023))
sin_par   # se excluyen: no se puede comparar el ganador entre años

pares <- drop_na(pares, ganador_2019, ganador_2023)

# Se agrupan en "Otros" los espacios que ganan pocos departamentos, para que la
# tabla no tenga celdas con frecuencias esperadas muy chicas
agrupar_pocos <- function(x, minimo) {
  ganados <- table(x)
  if_else(x %in% names(ganados[ganados < minimo]), "Otros", x)
}

orden_espacios <- c("Peronismo", "JxC", "Derecha liberal", "Tercera via", "Izquierda", "Otros")

pares <- pares |>
  mutate(
    ganador_2019 = factor(agrupar_pocos(ganador_2019, minimo_ganados), levels = orden_espacios),
    ganador_2023 = factor(agrupar_pocos(ganador_2023, minimo_ganados), levels = orden_espacios)
  ) |>
  mutate(across(c(ganador_2019, ganador_2023), fct_drop))

# ------------------------------------------------------------------------------
# 3. Test Chi cuadrado
# ------------------------------------------------------------------------------

tabla <- table(ganador_2019 = pares$ganador_2019, ganador_2023 = pares$ganador_2023)
addmargins(tabla)

prueba <- suppressWarnings(chisq.test(tabla, correct = FALSE))

# Supuesto: frecuencias esperadas >= 5. Si alguna celda no lo cumple, se
# confirma con el test exacto de Fisher (p-valor simulado)
celdas_chicas <- sum(prueba$expected < 5)
p_fisher <- NA_real_
if (celdas_chicas > 0) {
  set.seed(123)
  p_fisher <- fisher.test(tabla, simulate.p.value = TRUE, B = 1e5)$p.value
}

n <- sum(tabla)
v_cramer <- sqrt(unname(prueba$statistic) / (n * (min(dim(tabla)) - 1)))

# La V de Cramér mide asociación, no persistencia: se agrega el % de
# departamentos que repitió ganador frente al esperado si fueran independientes
mismos     <- intersect(rownames(tabla), colnames(tabla))
repitio    <- sum(diag(tabla[mismos, mismos])) / n
repitio_h0 <- sum(diag(prueba$expected[mismos, mismos])) / n

resultado <- tibble(
  departamentos        = n,
  excluidos_sin_par    = nrow(sin_par),
  chi_cuadrado         = unname(prueba$statistic),
  grados_libertad      = unname(prueba$parameter),
  p_valor              = prueba$p.value,
  celdas_esperada_menor_5 = celdas_chicas,
  p_valor_fisher       = p_fisher,
  v_cramer             = v_cramer,
  pct_repitio_ganador  = repitio * 100,
  pct_repitio_si_independientes = repitio_h0 * 100
) |>
  mutate(across(where(is.double), ~ round(.x, 4)))

resultado

residuos <- as_tibble(as.table(round(prueba$stdres, 2)), n = "residuo_estandarizado")
residuos

# ------------------------------------------------------------------------------
# 4. Gráfico: a quién votó en 2023 cada grupo de departamentos según su ganador 2019
# ------------------------------------------------------------------------------

etiquetas_espacio <- c("Peronismo" = "Peronismo", "JxC" = "JxC",
                       "Derecha liberal" = "LLA (derecha liberal)",
                       "Tercera via" = "Tercera vía", "Izquierda" = "Izquierda",
                       "Otros" = "Otros")
colores_espacio <- c("Peronismo" = "#0072B2", "JxC" = "#E69F00",
                     "LLA (derecha liberal)" = "#7B3294", "Tercera vía" = "#009E73",
                     "Izquierda" = "#D55E00", "Otros" = "grey60")

transiciones <- as_tibble(tabla, n = "departamentos") |>
  group_by(ganador_2019) |>
  mutate(total = sum(departamentos), pct = departamentos / total * 100) |>
  ungroup() |>
  filter(total >= minimo_ganados) |>
  arrange(factor(ganador_2019, levels = orden_espacios)) |>
  mutate(
    fila    = fct_inorder(paste0("Ganados por ", etiquetas_espacio[as.character(ganador_2019)],
                                 " en 2019 (", total, ")")),
    destino = factor(etiquetas_espacio[as.character(ganador_2023)], levels = etiquetas_espacio)
  )

retuvo_per <- with(filter(transiciones, ganador_2019 == "Peronismo", ganador_2023 == "Peronismo"), pct)
retuvo_jxc <- with(filter(transiciones, ganador_2019 == "JxC", ganador_2023 == "JxC"), pct)
coma0 <- label_number(accuracy = 1)
texto_p <- if (resultado$p_valor < 0.001) "p < 0,001" else
  paste0("p = ", label_number(accuracy = 0.001, decimal.mark = ",")(resultado$p_valor))

g_transiciones <- ggplot(transiciones, aes(x = pct, y = fct_rev(fila), fill = destino)) +
  geom_col(width = 0.6, colour = "white", linewidth = 0.5) +
  geom_text(aes(label = if_else(pct >= 6, paste0(coma0(pct), "%"), "")),
            position = position_stack(vjust = 0.5), colour = "white",
            size = 3.2, fontface = "bold") +
  scale_fill_manual(values = colores_espacio, name = "Ganador en 2023", drop = TRUE) +
  scale_x_continuous(labels = label_percent(scale = 1), expand = expansion(0)) +
  labs(
    title    = paste0("El peronismo retuvo el ", coma0(retuvo_per), "% de sus departamentos; ",
                      "JxC, el ", coma0(retuvo_jxc), "%"),
    subtitle = paste0("Ganador de 2023 en los departamentos según quién había ganado en 2019 ",
                      "(% de departamentos de cada fila).\nChi cuadrado = ",
                      label_number(accuracy = 0.1, decimal.mark = ",")(resultado$chi_cuadrado),
                      ", gl = ", resultado$grados_libertad, ", ", texto_p, "; V de Cramér = ",
                      label_number(accuracy = 0.01, decimal.mark = ",")(resultado$v_cramer),
                      "; n = ", n, " departamentos."),
    x        = "% de los departamentos ganados en 2019",
    y        = NULL,
    caption  = paste0(
      "Fuente: elaboración propia en base a la Dirección Nacional Electoral (DINE), ",
      "escrutinio provisorio 2019 y 2023 por mesa, agregado a departamento.\n",
      "Elecciones generales, cargo presidente, primera vuelta. Solo mesas escrutadas."
    )
  ) +
  tema_tp() +
  theme(panel.grid.major.y = element_blank())

# ------------------------------------------------------------------------------
# 5. Guardar
# ------------------------------------------------------------------------------

write_csv(pares,     "input/departamentos_ganador.csv")
write_csv(sin_par,   "output/tablas/04_departamentos_sin_par.csv")
write_csv(as_tibble(addmargins(tabla), n = "departamentos"),
          "output/tablas/04_tabla_contingencia.csv")
write_csv(resultado, "output/tablas/04_chi_cuadrado.csv")
write_csv(residuos,  "output/tablas/04_residuos_estandarizados.csv")
guardar_grafico(g_transiciones, "04_chi_cuadrado_transiciones.jpg", alto = 11)
