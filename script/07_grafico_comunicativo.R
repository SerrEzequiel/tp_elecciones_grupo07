# ==============================================================================
# 07_grafico_comunicativo.R
# Gráfico comunicativo (instancia 3, corregido): ¿el espacio que ganó cada
# provincia en 2019 la siguió ganando en 2023? Se construye directamente de los
# resultados (% de votos positivos), sin estimar flujos de votantes, que no se
# pueden observar con datos agregados.
#
# Lee:     input/provincias_espacios.csv    (script 01)
# Guarda:  output/tablas/07_retencion_provincias.csv
#          output/graficos/07_comunicativo_retencion.jpg
# ==============================================================================

library(tidyverse)
library(scales)

source("utils/tema_tp.R")
source("utils/fuente_tp.R")
source("utils/guardar_grafico.R")

espacios <- read_csv("input/provincias_espacios.csv", show_col_types = FALSE)

# ------------------------------------------------------------------------------
# 1. Ganador de cada provincia en 2019 y en 2023, y si lo retuvo
# ------------------------------------------------------------------------------

ganadores <- espacios |>
  group_by(anio, provincia) |>
  slice_max(pct, n = 1) |>
  ungroup() |>
  select(anio, provincia, ganador = espacio) |>
  pivot_wider(names_from = anio, values_from = ganador, names_prefix = "ganador_")

retencion <- espacios |>
  select(anio, provincia, espacio, pct) |>
  pivot_wider(names_from = anio, values_from = pct, names_prefix = "pct_") |>
  inner_join(ganadores, by = c("provincia", "espacio" = "ganador_2019")) |>
  rename(ganador_2019 = espacio) |>
  mutate(
    retuvo = ganador_2019 == ganador_2023,
    estado = factor(if_else(retuvo, "Siguió primero en 2023", "Perdió la provincia en 2023"),
                    levels = c("Siguió primero en 2023", "Perdió la provincia en 2023")),
    quien_gano = case_when(
      retuvo ~ "",
      ganador_2023 == "Derecha liberal" ~ "ganó LLA",
      ganador_2023 == "Peronismo"       ~ "ganó el peronismo",
      ganador_2023 == "JxC"             ~ "ganó JxC",
      TRUE ~ paste("ganó", ganador_2023)
    )
  )

# Resumen: cuántas provincias retuvo cada espacio ganador de 2019 (va al título)
resumen <- retencion |>
  group_by(ganador_2019) |>
  summarise(total = n(), retenidas = sum(retuvo))
resumen

per <- filter(resumen, ganador_2019 == "Peronismo")
jxc <- filter(resumen, ganador_2019 == "JxC")

# ------------------------------------------------------------------------------
# 2. Gráfico
# ------------------------------------------------------------------------------

# Orden de las filas: primero el bloque peronista y después JxC; dentro de cada
# bloque, primero las que retuvo y después las que perdió (de mayor a menor 2023)
retencion <- retencion |>
  mutate(bloque = factor(ganador_2019, levels = c("Peronismo", "JxC"))) |>
  arrange(bloque, desc(retuvo), desc(pct_2023)) |>
  group_by(bloque) |>
  mutate(fila = row_number()) |>
  ungroup() |>
  # posición vertical con un espacio entre los dos bloques para el encabezado
  mutate(y = -(row_number() + if_else(bloque == "JxC", 2.6, 0)))

encabezados <- tibble(
  bloque = c("Peronismo", "JxC"),
  y = c(min(retencion$y[retencion$bloque == "Peronismo"]) * 0 + 0.15,
        max(retencion$y[retencion$bloque == "JxC"]) + 1.25),
  texto = c(
    paste0("Ganadas por el PERONISMO en 2019: retuvo ", per$retenidas, " de ", per$total),
    paste0("Ganadas por JUNTOS POR EL CAMBIO en 2019: retuvo ", jxc$retenidas, " de ", jxc$total)
  )
)

colores_estado <- c("Siguió primero en 2023" = "#0072B2",
                    "Perdió la provincia en 2023" = "#D55E00")

primera <- slice(retencion, 1)  # fila donde rotulamos "2019" y "2023"

g_com <- ggplot(retencion, aes(y = y)) +
  # fondo suave para separar los dos bloques
  geom_segment(aes(x = 0, xend = 80, yend = y), colour = "grey93", linewidth = 0.3) +
  geom_segment(aes(x = pct_2019, xend = pct_2023, yend = y, colour = estado),
               linewidth = 0.9, alpha = 0.55, show.legend = FALSE,
               arrow = arrow(length = unit(1.5, "mm"), type = "closed")) +
  geom_point(aes(x = pct_2019), shape = 21, fill = "white", colour = "grey45",
             size = 2.4, stroke = 0.6) +
  geom_point(aes(x = pct_2023, colour = estado), size = 2.8) +
  # nombre de la provincia a la izquierda
  geom_text(aes(x = -1, label = provincia), hjust = 1, size = 3.1, colour = "grey15") +
  # quién ganó, solo en las que se perdieron
  geom_text(aes(x = pct_2019 + 1.5, label = quien_gano),
            hjust = 0, size = 2.8, colour = "#A84300", fontface = "bold") +
  # encabezados de cada bloque
  geom_text(data = encabezados, aes(x = -26, y = y, label = texto),
            hjust = 0, size = 3.4, fontface = "bold", colour = "grey10") +
  # rótulos directos de los años en la primera fila
  annotate("text", x = primera$pct_2019, y = primera$y + 0.75, label = "2019",
           size = 2.7, colour = "grey40") +
  annotate("text", x = primera$pct_2023, y = primera$y + 0.75, label = "2023",
           size = 2.7, colour = "#0072B2", fontface = "bold") +
  scale_colour_manual(values = colores_estado, name = NULL) +
  scale_x_continuous(limits = c(-26, 82), breaks = seq(0, 80, 20),
                     labels = label_percent(scale = 1), expand = expansion(0)) +
  scale_y_continuous(expand = expansion(add = c(0.8, 1.2))) +
  coord_cartesian(clip = "off") +
  labs(
    title = paste0("El peronismo retuvo ", per$retenidas, " de las ", per$total,
                   " provincias que ganó en 2019;\nJuntos por el Cambio, solo ",
                   jxc$retenidas, " de ", jxc$total),
    subtitle = paste0(
      "% de votos del espacio que ganó cada provincia en 2019, en 2019 (○) y en 2023 (●). ",
      "Ambos espacios perdieron votos en todas\nlas provincias, pero el peronismo ",
      "siguió primero en la mayoría. La Libertad Avanza (LLA) se quedó con 4 de las 6 de JxC."
    ),
    x = "% de votos positivos del espacio ganador en 2019",
    y = NULL,
    caption = fuente_tp(paste0(
      "Peronismo = Frente de Todos (2019) / Unión por la Patria (2023). ",
      "Entre Ríos 2019: JxC ganó por 0,1 puntos."
    ))
  ) +
  tema_tp() +
  theme(
    plot.title = element_text(face = "bold", size = 15, lineheight = 1.05),
    plot.subtitle = element_text(colour = "grey30", size = 9.3, lineheight = 1.15,
                                 margin = margin(b = 10)),
    axis.text.y = element_blank(),
    axis.title.x = element_text(size = 9, colour = "grey30", hjust = 0.62),
    panel.grid.major.y = element_blank(),
    axis.text.x = element_text(colour = "grey35"),
    legend.position = "top",
    legend.justification = "left",
    legend.text = element_text(size = 9.5)
  )

# ------------------------------------------------------------------------------
# 3. Guardar
# ------------------------------------------------------------------------------

retencion |>
  select(provincia, ganador_2019, ganador_2023, retuvo, pct_2019, pct_2023) |>
  mutate(across(c(pct_2019, pct_2023), ~ round(.x, 1))) |>
  write_csv("output/tablas/07_retencion_provincias.csv")

guardar_grafico(g_com, "07_comunicativo_retencion.jpg", alto = 19)
