# ==============================================================================
# 06_regresion_lla.R
# Tercer método (inferencia): regresión lineal por provincia.
# Pregunta: ¿La Libertad Avanza sacó más votos en 2023 donde Juntos por el
# Cambio era más fuerte en 2019? Si el avance de LLA fuera un "traspaso" desde
# JxC, el % de LLA debería crecer con el % que JxC tenía en 2019.
#
# Modelo 1: lla_2023 ~ jxc_2019
# Modelo 2: lla_2023 ~ jxc_2019 + grupo   (grupos del clustering, script 05)
# Robustez: modelo 1 sin las provincias influyentes
#
# Lee:     input/provincias_matriz.csv   (script 03)
#          input/provincias_grupos.csv   (script 05)
# Guarda:  output/tablas/06_regresion_coeficientes.csv
#          output/tablas/06_regresion_supuestos.csv
#          output/graficos/06_regresion_lla_jxc.jpg
# ==============================================================================

library(tidyverse)
library(scales)
library(ggrepel)
library(lmtest)     # coeftest(), bptest()
library(sandwich)   # errores estándar robustos (vcovHC)

source("utils/tema_tp.R")
source("utils/fuente_tp.R")
source("utils/guardar_grafico.R")

matriz <- read_csv("input/provincias_matriz.csv", show_col_types = FALSE)
grupos <- read_csv("input/provincias_grupos.csv", show_col_types = FALSE)

# La Libertad Avanza es la "Derecha liberal" de 2023
datos <- matriz |>
  left_join(select(grupos, provincia, grupo), by = "provincia") |>
  transmute(
    provincia,
    lla_2023       = derecha_liberal_2023,
    jxc_2019,
    peronismo_2019,
    # categoría de referencia: el grupo más parejo en 2019
    grupo = fct_relevel(factor(grupo), "Bicoalición en 2019")
  )

# ------------------------------------------------------------------------------
# 1. Por qué un solo predictor de 2019
# ------------------------------------------------------------------------------

# JxC y peronismo en 2019 están casi perfectamente correlacionados (r ≈ -0,94):
# en 2019 la elección fue de dos. Incluir ambos daría multicolinealidad, así que
# se usa JxC 2019, que es la variable de la pregunta.
cor(datos$jxc_2019, datos$peronismo_2019)

# ------------------------------------------------------------------------------
# 2. Estimación
# ------------------------------------------------------------------------------

modelo_1 <- lm(lla_2023 ~ jxc_2019, data = datos)
modelo_2 <- lm(lla_2023 ~ jxc_2019 + grupo, data = datos)

summary(modelo_1)
summary(modelo_2)

# ------------------------------------------------------------------------------
# 3. Supuestos
# ------------------------------------------------------------------------------

# Normalidad de los residuos (Shapiro-Wilk) y homocedasticidad (Breusch-Pagan).
# Con 24 provincias los tests tienen poca potencia, así que además se reportan
# errores estándar robustos (HC1), válidos aunque haya heterocedasticidad.
# Influencia: distancia de Cook > 4/n marca provincias con mucho peso.

evaluar_supuestos <- function(ajuste, nombre) {
  cook          <- cooks.distance(ajuste)
  shapiro_p     <- shapiro.test(residuals(ajuste))$p.value
  bp_p          <- bptest(ajuste)$p.value
  influyentes   <- paste(datos$provincia[cook > 4 / nrow(datos)], collapse = ", ")
  tibble(
    modelo                 = nombre,
    shapiro_p              = shapiro_p,
    breusch_pagan_p        = bp_p,
    provincias_influyentes = influyentes
  )
}

supuestos <- bind_rows(
  evaluar_supuestos(modelo_1, "Modelo 1"),
  evaluar_supuestos(modelo_2, "Modelo 2")
) |>
  mutate(across(where(is.numeric), ~ round(.x, 3)))

supuestos

# ------------------------------------------------------------------------------
# 4. Coeficientes con errores estándar robustos (HC1)
# ------------------------------------------------------------------------------

tabla_coeficientes <- function(ajuste, nombre) {
  robusto <- coeftest(ajuste, vcov. = vcovHC(ajuste, type = "HC1"))
  ic      <- coefci(ajuste, vcov. = vcovHC(ajuste, type = "HC1"), level = 0.95)
  resumen <- summary(ajuste)
  tibble(
    modelo        = nombre,
    termino       = rownames(robusto),
    coeficiente   = robusto[, "Estimate"],
    error_robusto = robusto[, "Std. Error"],
    t             = robusto[, "t value"],
    p_valor       = robusto[, "Pr(>|t|)"],
    ic_inferior   = ic[, 1],
    ic_superior   = ic[, 2],
    r2            = resumen$r.squared,
    r2_ajustado   = resumen$adj.r.squared,
    n             = nobs(ajuste)
  )
}

# Robustez: el modelo 1 sin las provincias influyentes (distancia de Cook)
influyentes <- datos$provincia[cooks.distance(modelo_1) > 4 / nrow(datos)]
modelo_1_sin <- lm(lla_2023 ~ jxc_2019, data = filter(datos, !provincia %in% influyentes))

coeficientes <- bind_rows(
  tabla_coeficientes(modelo_1,     "Modelo 1"),
  tabla_coeficientes(modelo_2,     "Modelo 2"),
  tabla_coeficientes(modelo_1_sin, "Modelo 1 sin provincias influyentes")
) |>
  mutate(across(where(is.numeric), ~ round(.x, 3)))

coeficientes

# ------------------------------------------------------------------------------
# 5. Gráfico: % de LLA 2023 según % de JxC 2019
# ------------------------------------------------------------------------------

coma  <- label_number(accuracy = 0.01, decimal.mark = ",")
coma3 <- label_number(accuracy = 0.001, decimal.mark = ",")
b1 <- filter(coeficientes, modelo == "Modelo 1", termino == "jxc_2019")

colores_grupo <- c("Mayor caída del peronismo" = "#E69F00",
                   "Bicoalición en 2019"       = "#0072B2",
                   "Peronismo persistente"     = "#009E73")

datos_grafico <- datos |>
  mutate(grupo = factor(as.character(grupo), levels = names(colores_grupo)))

g_regresion <- ggplot(datos_grafico, aes(jxc_2019, lla_2023)) +
  geom_smooth(method = "lm", formula = y ~ x, colour = "grey30", fill = "grey85",
              linewidth = 0.7) +
  geom_point(aes(colour = grupo, shape = grupo), size = 2.6) +
  geom_text_repel(aes(label = provincia), size = 2.8, colour = "grey20",
                  bg.color = "white", bg.r = 0.15, min.segment.length = 0.2,
                  seed = 1) +
  annotate("label", x = 62, y = 18, hjust = 1, size = 3, label.size = 0,
           fill = "grey95", colour = "grey15", lineheight = 1.1,
           label = paste0("Pendiente: ", coma(b1$coeficiente),
                          " (IC 95%: ", coma(b1$ic_inferior), " a ", coma(b1$ic_superior), ")\n",
                          "p = ", coma3(b1$p_valor), " · R² = ", coma(b1$r2), " · n = 24")) +
  scale_colour_manual(values = colores_grupo, name = "Grupo") +
  scale_shape_manual(values = c(17, 16, 15), name = "Grupo") +
  scale_x_continuous(labels = label_percent(scale = 1)) +
  scale_y_continuous(labels = label_percent(scale = 1)) +
  labs(
    title    = "El voto de LLA en 2023 no dependió de cuán fuerte era JxC en 2019",
    subtitle = paste0("Cada punto es una provincia. Línea: regresión lineal con su intervalo de confianza del 95%. ",
                      "Los ejes no empiezan en cero."),
    x        = "% de votos de Juntos por el Cambio en 2019",
    y        = "% de votos de La Libertad Avanza en 2023",
    caption  = fuente_tp("Errores estándar robustos (HC1).")
  ) +
  tema_tp()

# ------------------------------------------------------------------------------
# 6. Guardar
# ------------------------------------------------------------------------------

write_csv(coeficientes, "output/tablas/06_regresion_coeficientes.csv")
write_csv(supuestos,    "output/tablas/06_regresion_supuestos.csv")
guardar_grafico(g_regresion, "06_regresion_lla_jxc.jpg", alto = 15)
