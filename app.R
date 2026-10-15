# ==============================================================================
# 1. LIBRERÍAS Y CONFIGURACIÓN
# ==============================================================================
library(shiny)
library(shinydashboard)
library(leaflet)
library(sf)
library(dplyr)
library(ggplot2)
library(scales)
library(shinycssloaders)
library(DT)
library(rlang)
format_value <- function(x) {
  scales::number(x, big.mark = ".", decimal.mark = ",")
}

casos_nacional <- readRDS("casos_nacional.rds")
casos_departamental <- readRDS("casos_departamental.rds")

deptos_choices <- c(
  "Toda Colombia" = "Todos",
  sort(unique(casos_nacional$departamento))
)
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
# ==============================================================================
# 3. INTERFAZ DE USUARIO
# ==============================================================================
ui <- dashboardPage(
  skin = "blue",
  dashboardHeader(title = "Observatorio Colombia"),
  dashboardSidebar(
    sidebarMenu(
      menuItem("Análisis de Datos", tabName = "analisis_tab", icon = icon("map-location-dot")),
      menuItem("Tabla de Registros", tabName = "tabla_tab", icon = icon("table"))
    ),
    hr(),
    div(style="padding: 15px;",
        radioButtons("map_view_mode", "Visualizar por:", choices = c("Municipal" = "municipal", "Departamental" = "departamental")),
        selectInput("departamento_filter", "Departamento:", choices = deptos_choices),
        selectInput("variable", "Seleccione Indicador:", choices = variable_options)
    )
  ),
  dashboardBody(
    tags$head(tags$style(HTML("
      .content-wrapper { background-color: #f0f2f5 !important; }
      .box { border-radius: 12px; }
    "))),
    
    tabItems(
      tabItem(tabName = "analisis_tab",
              fluidRow(
                valueBoxOutput("box_total", width = 4),
                valueBoxOutput("box_top", width = 4),
                valueBoxOutput("box_avg", width = 4)
              ),
              fluidRow(
                box(title = "Mapa de Intensidad", status = "primary", solidHeader = TRUE, width = 7,
                    leafletOutput("map", height = 650) %>% withSpinner(type = 6)),
                box(title = "Principales Registros", status = "primary", solidHeader = TRUE, width = 5,
                    plotOutput("ranking_chart", height = 650))
              )
      ),
      tabItem(tabName = "tabla_tab",
              box(title = "Datos Completos", status = "primary", width = 12, DTOutput("data_table"))
      )
    )
  )
)

# ==============================================================================
# 4. SERVIDOR
# ==============================================================================
server <- function(input, output, session) {
  
  data_filtered <- reactive({
    df <- if(input$map_view_mode == "municipal") casos_nacional else casos_departamental
    if (input$departamento_filter != "Todos") df <- df[df$departamento == input$departamento_filter, ]
    return(df)
  })
  
  output$box_total <- renderValueBox({
    df <- data_filtered()
    col_t <- if(input$map_view_mode == "municipal") input$variable else paste0(input$variable, "_dep")
    total <- sum(df[[col_t]], na.rm = TRUE)
    valueBox(format_value(total), "Total Nacional", icon = icon("chart-bar"), color = "blue")
  })
  
  output$box_top <- renderValueBox({
    df <- data_filtered()
    col_t <- if(input$map_view_mode == "municipal") input$variable else paste0(input$variable, "_dep")
    idx <- which.max(df[[col_t]])
    name <- if(input$map_view_mode == "municipal") df$municipio[idx] else df$departamento[idx]
    valueBox(name, "Líder de Tabla", icon = icon("medal"), color = "light-blue")
  })
  
  output$box_avg <- renderValueBox({
    df <- data_filtered()
    col_t <- if(input$map_view_mode == "municipal") input$variable else paste0(input$variable, "_dep")
    prom <- mean(df[[col_t]], na.rm = TRUE)
    valueBox(format_value(prom), "Promedio Zona", icon = icon("calculator"), color = "teal")
  })
  
  output$map <- renderLeaflet({
    leaflet() %>% 
      addProviderTiles(providers$Esri.WorldTopoMap) %>% 
      setView(lng = -74.297, lat = 4.570, zoom = 5)
  })
  
  observe({
    req(input$variable)
    data_sf <- data_filtered()
    col_target <- if(input$map_view_mode == "municipal") input$variable else paste0(input$variable, "_dep")
    
    if(!col_target %in% names(data_sf) || nrow(data_sf) == 0) return()
    
    vals <- data_sf[[col_target]]
    
    # MEJORA VISUAL: Paleta de alto contraste (Amarillo a Rojo oscuro)
    pal <- colorNumeric(palette = "YlOrRd", domain = vals, na.color = "#bdc3c7")
    
    popups <- paste0(
      "<div style='padding: 5px; color: #2c3e50;'>",
      "<b>Lugar:</b> ", if(input$map_view_mode == "municipal") data_sf$municipio else data_sf$departamento, "<br>",
      "<b>Cantidad:</b> <span style='color:#e74c3c; font-weight:bold;'>", format_value(vals), "</span></div>"
    )
    
    leafletProxy("map", data = data_sf) %>%
      clearShapes() %>% clearControls() %>%
      addPolygons(
        fillColor = ~pal(vals), 
        weight = 1.2,          # Bordes más gruesos para definir la forma
        color = "#4d4d4d",      # Borde gris oscuro para contraste
        fillOpacity = 0.85,    # Más sólido para resaltar sobre el mapa topográfico
        label = ~if(input$map_view_mode == "municipal") municipio else departamento,
        popup = popups,
        highlightOptions = highlightOptions(weight = 3, color = "black", bringToFront = TRUE)
      ) %>%
      addLegend("bottomright", pal = pal, values = vals, title = "Intensidad", layerId = "leg")
  })
  
  output$ranking_chart <- renderPlot({
    req(input$variable)
    df_rank <- st_drop_geometry(casos_nacional)
    if (input$departamento_filter != "Todos") df_rank <- df_rank[df_rank$departamento == input$departamento_filter, ]
    
    df_rank <- df_rank %>% 
      filter(!is.na(!!sym(input$variable))) %>% 
      arrange(desc(!!sym(input$variable))) %>% 
      head(10)
    
    if(nrow(df_rank) == 0) return(NULL)
    
    ggplot(df_rank, aes(x = reorder(municipio, !!sym(input$variable)), y = !!sym(input$variable))) +
      geom_col(fill = "#1b4f72", width = 0.7) + 
      geom_text(aes(y = !!sym(input$variable) / 2, 
                    label = format_value(!!sym(input$variable))), 
                color = "white", fontface = "bold", size = 5) +
      coord_flip() + 
      theme_minimal() +
      theme(
        plot.background = element_rect(fill = "#d6eaf8", color = NA),
        panel.background = element_rect(fill = "#d6eaf8", color = NA),
        panel.grid.major.y = element_blank(),
        axis.text = element_text(color = "#1b2631", face = "bold", size = 11)
      ) +
      labs(x = NULL, y = "Cifras")
  })
  
  output$data_table <- renderDT({
    datatable(st_drop_geometry(data_filtered()), options = list(pageLength = 10, scrollX = TRUE))
  })
}

shinyApp(ui, server)