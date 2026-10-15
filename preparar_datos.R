# ==============================================================================
# 2. CARGA Y PREPARACIÓN DE DATOS
# ==============================================================================
library(sf)
library(dplyr)
library(openxlsx)
library(rlang)
library(magrittr)

limpiar_texto <- function(x) {
  if (is.null(x)) return(NULL)
  x <- toupper(as.character(x))
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  x <- gsub("[^[:alnum:][:space:]]", "", x) 
  return(trimws(x))
}

format_value <- function(x) {
  ifelse(is.na(x), "0", format(round(x, 1), big.mark = ",", decimal.mark = ".", trim = TRUE))
}
variable_options <- c(
  "Casos de homicidio (Total)"       = "casos_homicidio",
  "Homicidios por cada 100,000 hab." = "homicidios_por_cada_100000_habitantes",
  "Total nacimientos"                = "total_nacimientos",
  "Madres menores de 14"             = "madres_menores_de_14",
  "Madres sin bachillerato"          = "madres_sin_bachiderato",
  "Madres con bachillerato"          = "madres_con_bachiderato",
  "Madres prof. o técnicas"          = "madres_profecionales_o_tecnicas",
  "Casos homicidio (Hombres)"        = "casos_homicidio_hombre",
  "Tasa homicidios (Hombres)"        = "tasa_homicidios_hombres",
  "Casos homicidio (Mujeres)"        = "casos_homicidio_mujer",
  "Tasa homicidios (Mujeres)"        = "tasa_homicidios_mujeres"
)

colombia_sf <- st_read("gadm41_COL_2.shp", quiet = TRUE) %>%
  rename(departamento = NAME_1, municipio = NAME_2) %>%
  mutate(mun_key = limpiar_texto(municipio), dep_key = limpiar_texto(departamento))

info_mun <- read.xlsx("colombia_atributos.xlsx", sheet = "Hoja3")
names(info_mun) <- names(info_mun) %>% tolower() %>% gsub("\\.+", "_", .)

info_mun <- info_mun %>%
  mutate(dep_key = limpiar_texto(!!sym(names(info_mun)[1])),
         mun_key = limpiar_texto(!!sym(names(info_mun)[2]))) %>%
  select(-1, -2)

info_dep <- read.xlsx("colombia_atributos.xlsx", sheet = "Hoja1")
names(info_dep) <- names(info_dep) %>% tolower() %>% gsub("\\.+", "_", .)

info_dep <- info_dep %>%
  mutate(dep_key = limpiar_texto(!!sym(names(info_dep)[1]))) %>%
  select(-1) %>% 
  rename_with(~ paste0(., "_dep"), .cols = -dep_key)

casos_nacional <- colombia_sf %>%
  left_join(info_mun, by = c("mun_key", "dep_key")) %>% 
  left_join(info_dep, by = "dep_key") %>% 
  st_as_sf() %>% st_transform(crs = 4326)

vars_all <- c(variable_options, names(info_dep)[grepl("_dep$", names(info_dep))])
for (col in vars_all) {
  if (col %in% names(casos_nacional)) {
    casos_nacional[[col]] <- suppressWarnings(as.numeric(casos_nacional[[col]]))
  }
}

casos_departamental <- colombia_sf %>%
  group_by(departamento) %>%
  summarise(geometry = st_union(geometry), .groups = 'drop') %>%
  left_join(
    casos_nacional %>% st_drop_geometry() %>% group_by(departamento) %>% 
      summarise(across(ends_with("_dep"), ~first(.)), .groups = 'drop'),
    by = "departamento"
  ) %>% st_as_sf()

deptos_choices <- c("Toda Colombia" = "Todos", sort(unique(casos_nacional$departamento)))

# Simplificación geométrica para reducir peso
casos_nacional <- st_simplify(casos_nacional, dTolerance = 200)
casos_departamental <- st_simplify(casos_departamental, dTolerance = 200)

saveRDS(casos_nacional, "casos_nacional.rds")
saveRDS(casos_departamental, "casos_departamental.rds")

print("Archivos RDS creados correctamente")
