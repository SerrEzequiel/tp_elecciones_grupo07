# ==============================================================================
# 05_clustering_pca.R
# Método cuantitativo: k-means sobre las 24 provincias según su perfil de voto
# 2019-2023, con PCA para visualizar. Incluye la elección de k, la comparación
# con un clustering jerárquico (Ward) y la repetición sin provincias atípicas.
#
# Lee:     input/provincias_matriz.csv     (script 03)
#          input/provincias_atipicas.csv   (script 03)
# Guarda:  output/tablas/05_eleccion_k.csv
#          output/tablas/05_grupos.csv
#          output/tablas/05_perfil_grupos.csv
#          output/tablas/05_robustez.csv
#          output/tablas/05_pca_varianza.csv
#          output/graficos/05_eleccion_k.jpg
#          output/graficos/05_exploratorio_clusters_pca.jpg   (gráfico exploratorio, instancia 3)
#          input/provincias_grupos.csv
# ==============================================================================

library(tidyverse)
library(scales)
library(cluster)    # silhouette
library(ggrepel)
library(patchwork)

source("utils/tema_tp.R")
source("utils/fuente_tp.R")
source("utils/etiqueta_variable.R")
source("utils/guardar_grafico.R")

matriz <- read_csv("input/provincias_matriz.csv", show_col_types = FALSE) |>
  column_to_rownames("provincia")

provincias_atipicas <- read_csv("input/provincias_atipicas.csv", show_col_types = FALSE) |>
  pull(provincia)

# Estandarización z-score: la izquierda ronda pocos puntos y el peronismo decenas;
# sin estandarizar, las variables grandes dominarían la distancia
x <- scale(matriz)

semilla <- 123
inicios <- 50   # k-means depende del punto de partida: 50 inicios aleatorios

# ------------------------------------------------------------------------------
# 1. Cantidad de grupos: método del codo y silhouette media (k = 2 a 6)
# ------------------------------------------------------------------------------

eleccion_k <- map_dfr(2:6, function(k) {
  set.seed(semilla)
  km <- kmeans(x, centers = k, nstart = inicios)
  tibble(
    k                  = k,
    within_total       = km$tot.withinss,
    varianza_explicada = km$betweenss / km$totss * 100,
    silhouette_media   = mean(silhouette(km$cluster, dist(x))[, "sil_width"])
  )
})

eleccion_k

# Se elige k = 3: la silhouette de k = 4 es apenas mayor, con 24 provincias se
# prefieren grupos más grandes y Ward confirma la partición (ver sección 3)
k_elegido <- 3

g_codo <- ggplot(eleccion_k, aes(k, within_total)) +
  geom_line(colour = "grey50") +
  geom_point(aes(colour = k == k_elegido), size = 2.5, show.legend = FALSE) +
  scale_colour_manual(values = c("FALSE" = "grey50", "TRUE" = "#0072B2")) +
  labs(title = "Método del codo", x = "Cantidad de grupos (k)",
       y = "Suma de cuadrados intragrupo") +
  tema_tp() +
  theme(plot.title = element_text(size = 11), plot.title.position = "panel")

g_silhouette <- ggplot(eleccion_k, aes(k, silhouette_media)) +
  geom_line(colour = "grey50") +
  geom_point(aes(colour = k == k_elegido), size = 2.5, show.legend = FALSE) +
  scale_colour_manual(values = c("FALSE" = "grey50", "TRUE" = "#0072B2")) +
  scale_y_continuous(labels = label_number(accuracy = 0.001, decimal.mark = ",")) +
  labs(title = "Silueta media (más alta = mejor)",
       x = "Cantidad de grupos (k)", y = "Silueta media (silhouette)") +
  tema_tp() +
  theme(plot.title = element_text(size = 11), plot.title.position = "panel")

g_eleccion_k <- (g_codo | g_silhouette) +
  plot_annotation(
    title    = "Elección de la cantidad de grupos: k = 3",
    subtitle = "k-means sobre 24 provincias y 10 variables estandarizadas. En azul, el k elegido. Los ejes verticales no empiezan en cero.",
    caption  = fuente_tp(),
    theme    = tema_tp()
  )

# ------------------------------------------------------------------------------
# 2. k-means con k = 3
# ------------------------------------------------------------------------------

set.seed(semilla)
km <- kmeans(x, centers = k_elegido, nstart = inicios)

# Nombre de cada grupo según su perfil (no según la región)
perfil_crudo <- as_tibble(matriz, rownames = "provincia") |>
  mutate(cluster = km$cluster) |>
  group_by(cluster) |>
  summarise(n = n(), across(where(is.numeric), mean), .groups = "drop")

id_persistente <- perfil_crudo$cluster[which.max(perfil_crudo$peronismo_2023)]
id_bicoalicion <- perfil_crudo$cluster[which.min(abs(perfil_crudo$peronismo_2019 -
                                                     perfil_crudo$jxc_2019))]
id_cambio      <- setdiff(1:3, c(id_persistente, id_bicoalicion))

nombres_grupo <- tibble(
  cluster = c(id_cambio, id_bicoalicion, id_persistente),
  grupo   = c("Mayor caída del peronismo", "Bicoalición en 2019", "Peronismo persistente")
)

grupos <- tibble(provincia = rownames(x), cluster = km$cluster) |>
  left_join(nombres_grupo, by = "cluster") |>
  arrange(grupo, provincia)

perfil_grupos <- perfil_crudo |>
  left_join(nombres_grupo, by = "cluster") |>
  relocate(grupo, .after = cluster) |>
  mutate(across(where(is.double), ~ round(.x, 1)))

perfil_grupos

# ------------------------------------------------------------------------------
# 3. Robustez: jerárquico (Ward) y k-means sin las provincias atípicas
# ------------------------------------------------------------------------------

ward <- cutree(hclust(dist(x), method = "ward.D2"), k = k_elegido)
coincidencia_ward <- max(table(km$cluster, ward) |> apply(1, max) |> sum(),
                         table(ward, km$cluster) |> apply(1, max) |> sum())

x_sin <- scale(matriz[!rownames(matriz) %in% provincias_atipicas, ])
set.seed(semilla)
km_sin <- kmeans(x_sin, centers = k_elegido, nstart = inicios)
tabla_sin <- table(km$cluster[rownames(x_sin)], km_sin$cluster)
coincidencia_sin <- sum(apply(tabla_sin, 2, max))

robustez <- tibble(
  prueba       = c("Jerárquico Ward (k = 3)", "k-means sin provincias atípicas"),
  provincias   = c(nrow(x), nrow(x_sin)),
  mismo_grupo  = c(coincidencia_ward, coincidencia_sin)
)

robustez

# ------------------------------------------------------------------------------
# 4. PCA para visualizar los grupos en dos dimensiones
# ------------------------------------------------------------------------------

pca <- prcomp(x)
pca_varianza <- tibble(
  componente         = paste0("CP", seq_along(pca$sdev)),
  varianza_explicada = summary(pca)$importance[2, ] * 100,
  acumulada          = summary(pca)$importance[3, ] * 100
) |>
  mutate(across(where(is.numeric), ~ round(.x, 1)))

pca_varianza
var_exp <- pca_varianza$varianza_explicada[1:2]
coma <- label_number(accuracy = 0.1, decimal.mark = ",")

etiqueta_grupo <- grupos |>
  count(grupo) |>
  mutate(etiqueta = paste0(grupo, " (", n, ")"))

puntos <- as_tibble(pca$x[, 1:2], rownames = "provincia") |>
  left_join(grupos, by = "provincia") |>
  left_join(etiqueta_grupo, by = "grupo") |>
  mutate(etiqueta = factor(etiqueta, levels = etiqueta_grupo$etiqueta[
    match(c("Mayor caída del peronismo", "Bicoalición en 2019", "Peronismo persistente"),
          etiqueta_grupo$grupo)]))

contornos <- puntos |> group_by(etiqueta) |> slice(chull(PC1, PC2)) |> ungroup()

escala <- 0.85 * max(abs(pca$x[, 1:2])) / max(abs(pca$rotation[, 1:2]))
flechas <- as_tibble(pca$rotation[, 1:2] * escala, rownames = "variable") |>
  mutate(anio     = str_extract(variable, "\\d{4}"),
         etiqueta = etiqueta_variable(variable))

# Rótulos de provincias y de flechas en una sola capa, para que no se pisen
rotulos <- bind_rows(
  transmute(puntos, x = PC1, y = PC2, texto = provincia, estilo = "plain",
            color = "grey10", tam = 2.9, linea = "grey50"),
  transmute(flechas, x = PC1 * 1.06, y = PC2 * 1.06, texto = etiqueta,
            estilo = "italic", color = "grey35", tam = 2.55, linea = "grey70")
)

colores_grupo <- setNames(c("#E69F00", "#0072B2", "#009E73"), levels(puntos$etiqueta))
formas_grupo  <- setNames(c(17, 16, 15), levels(puntos$etiqueta))

g_exploratorio <- ggplot() +
  geom_hline(yintercept = 0, colour = "grey75", linewidth = 0.3) +
  geom_vline(xintercept = 0, colour = "grey75", linewidth = 0.3) +
  geom_polygon(data = contornos, aes(PC1, PC2, fill = etiqueta, colour = etiqueta),
               alpha = 0.10, linewidth = 0.4, show.legend = FALSE) +
  geom_segment(data = flechas, aes(x = 0, y = 0, xend = PC1, yend = PC2, linetype = anio),
               colour = "grey45", linewidth = 0.35,
               arrow = arrow(length = unit(1.6, "mm"), type = "closed")) +
  geom_point(data = puntos, aes(PC1, PC2, colour = etiqueta, shape = etiqueta), size = 2.6) +
  geom_text_repel(data = rotulos, aes(x, y, label = texto, fontface = estilo),
                  colour = rotulos$color, size = rotulos$tam,
                  segment.colour = rotulos$linea, segment.size = 0.3,
                  bg.color = "white", bg.r = 0.15, box.padding = 0.35,
                  point.padding = 0.15, min.segment.length = 0,
                  max.overlaps = Inf, seed = 2) +
  scale_colour_manual(values = colores_grupo, name = "Grupo") +
  scale_fill_manual(values = colores_grupo, guide = "none") +
  scale_shape_manual(values = formas_grupo, name = "Grupo") +
  scale_linetype_manual(values = c("2019" = "dashed", "2023" = "solid"),
                        name = "Variables (% de votos)") +
  scale_x_continuous(labels = label_number(decimal.mark = ",")) +
  scale_y_continuous(labels = label_number(decimal.mark = ",")) +
  labs(
    title    = "Tres perfiles provinciales de voto presidencial, 2019 y 2023",
    subtitle = paste0(
      "Componentes principales y clusters k-means sobre 10 variables estandarizadas: ",
      "% de votos de 5 espacios en 2019 y 2023.\n",
      "Cada punto es una provincia. Las flechas muestran hacia dónde crece cada variable."
    ),
    x = paste0("Componente principal 1 (", coma(var_exp[1]), "% de la varianza)"),
    y = paste0("Componente principal 2 (", coma(var_exp[2]), "% de la varianza)"),
    caption = fuente_tp(paste0(
      "Espacios: Peronismo (FdT / UxP), JxC, Derecha liberal (Unite + NOS / LLA), ",
      "Tercera vía (Consenso Federal / Hacemos), Izquierda (FIT-U)."
    ))
  ) +
  guides(colour = guide_legend(order = 1, ncol = 1),
         shape  = guide_legend(order = 1, ncol = 1),
         linetype = guide_legend(order = 2, ncol = 1,
                                 override.aes = list(colour = "grey45"))) +
  tema_tp() +
  theme(legend.title = element_text(size = 9, face = "bold"),
        legend.text  = element_text(size = 8.5))

# ------------------------------------------------------------------------------
# 5. Guardar
# ------------------------------------------------------------------------------

write_csv(eleccion_k,    "output/tablas/05_eleccion_k.csv")
write_csv(grupos,        "output/tablas/05_grupos.csv")
write_csv(perfil_grupos, "output/tablas/05_perfil_grupos.csv")
write_csv(robustez,      "output/tablas/05_robustez.csv")
write_csv(pca_varianza,  "output/tablas/05_pca_varianza.csv")

guardar_grafico(g_eleccion_k,   "05_eleccion_k.jpg", alto = 10)
guardar_grafico(g_exploratorio, "05_exploratorio_clusters_pca.jpg", alto = 17)

write_csv(grupos, "input/provincias_grupos.csv")
