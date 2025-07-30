package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
)

// CloudEvent represents the structure of a Dapr CloudEvent
type CloudEvent struct {
	ID              string                 `json:"id"`
	Source          string                 `json:"source"`
	SpecVersion     string                 `json:"specversion"`
	Type            string                 `json:"type"`
	DataContentType string                 `json:"datacontenttype"`
	Data            map[string]interface{} `json:"data"`
	Subject         string                 `json:"subject,omitempty"`
	Time            string                 `json:"time,omitempty"`
}

// getEnvVar gets an environment variable with optional fallback variables
func getEnvVar(varName string, fallbackVarNames ...string) string {
	value := os.Getenv(varName)
	if value == "" {
		for _, fallbackVarName := range fallbackVarNames {
			value = os.Getenv(fallbackVarName)
			if value != "" {
				break
			}
		}
		if value == "" && len(fallbackVarNames) == 0 {
			// If no fallback provided, this is a required variable
			log.Printf("%s is not set and no fallback provided", varName)
			os.Exit(1)
		}
		// If fallback provided but empty, use the last fallback as default
		if value == "" && len(fallbackVarNames) > 0 {
			value = fallbackVarNames[len(fallbackVarNames)-1]
		}
	}
	return value
}

// initDaprDatabase initializes the Dapr-based database connection
func initDaprDatabase() (*OrderService, error) {
	stateStoreName := getEnvVar("STATE_STORE_NAME", "statestore")
	daprPort := getEnvVar("DAPR_HTTP_PORT", "3500")
	
	daprRepo := &DaprStateRepository{
		stateStoreName: stateStoreName,
		daprPort:       daprPort,
	}
	
	return NewOrderService(daprRepo), nil
}

func main() {
	log.Println("makeline-service started with Dapr")

	orderService, err := initDaprDatabase()
	if err != nil {
		log.Fatal("Failed to initialize Dapr database:", err)
	}

	// Initialize Gin router
	r := gin.Default()

	// Dapr subscription configuration endpoint
	r.GET("/dapr/subscribe", getSubscriptions)

	// Dapr order handler endpoint  
	r.POST("/orders", OrderMiddleware(orderService), handleDaprOrder)

	// API endpoints (compatible with existing makeline service)
	api := r.Group("/")
	{
		api.GET("/orders", fetchOrders)        // Keep for backwards compatibility
		api.GET("/order/fetch", fetchOrders)   // Virtual-worker expects this endpoint
		api.GET("/order/:id", getOrder)
		api.POST("/order/:id", updateOrder)
		api.PUT("/order", updateOrder)         // Virtual-worker expects this endpoint
	}

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "healthy"})
	})

	port := getEnvVar("PORT", "3001")
	log.Printf("Server starting on port %s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}

// getSubscriptions returns the Dapr subscription configuration
func getSubscriptions(c *gin.Context) {
	pubsubName := getEnvVar("PUBSUB_NAME", "orderprocessing")
	topicName := getEnvVar("ORDER_TOPIC_NAME", "orders")
	
	subscriptions := []map[string]interface{}{
		{
			"pubsubname": pubsubName,
			"topic":      topicName,
			"route":      "/orders",
		},
	}
	c.JSON(http.StatusOK, subscriptions)
}

// handleDaprOrder processes incoming orders from Dapr pub/sub
func handleDaprOrder(c *gin.Context) {
	orderService, ok := c.MustGet("orderService").(*OrderService) 
	if !ok {
		log.Printf("Failed to get order service from context")
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	var cloudEvent CloudEvent
	if err := c.ShouldBindJSON(&cloudEvent); err != nil {
		log.Printf("Failed to bind CloudEvent: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid CloudEvent format"})
		return
	}

	log.Printf("Received CloudEvent: ID=%s, Type=%s, Source=%s", cloudEvent.ID, cloudEvent.Type, cloudEvent.Source)

	// Extract order data from CloudEvent
	orderData, err := json.Marshal(cloudEvent.Data)
	if err != nil {
		log.Printf("Failed to marshal order data: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid order data"})
		return
	}

	var order Order
	if err := json.Unmarshal(orderData, &order); err != nil {
		log.Printf("Failed to unmarshal order: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid order format"})
		return
	}

	// Set initial status if not set
	if order.Status == 0 {
		order.Status = 1 // Processing
	}

	log.Printf("Processing order: %s", order.OrderID)

	// Save order using Dapr state store
	orders := []Order{order}
	if err := orderService.repo.InsertOrders(orders); err != nil {
		log.Printf("Failed to save order %s: %v", order.OrderID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save order"})
		return
	}

	log.Printf("Successfully processed order: %s", order.OrderID)

	// Return success to Dapr
	c.JSON(http.StatusOK, gin.H{"status": "success"})
}

// OrderMiddleware is a middleware function that injects the order service into the request context
func OrderMiddleware(orderService *OrderService) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Set("orderService", orderService)
		c.Next()
	}
}

// Fetches orders - for Dapr mode, orders come via pub/sub
func fetchOrders(c *gin.Context) {
	client, ok := c.MustGet("orderService").(*OrderService)
	if !ok {
		log.Printf("Failed to get order service")
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	// In Dapr mode, orders are processed via pub/sub, so we just return pending orders
	orders, err := client.repo.GetPendingOrders()
	if err != nil {
		log.Printf("Failed to get pending orders: %s", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	c.IndentedJSON(http.StatusOK, orders)
}

// Gets a single order from database by order ID
func getOrder(c *gin.Context) {
	client, ok := c.MustGet("orderService").(*OrderService)
	if !ok {
		log.Printf("Failed to get order service")
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	orderID := c.Param("id")
	order, err := client.repo.GetOrder(orderID)
	if err != nil {
		log.Printf("Failed to get order %s: %s", orderID, err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	c.IndentedJSON(http.StatusOK, order)
}

// Updates an existing order
func updateOrder(c *gin.Context) {
	client, ok := c.MustGet("orderService").(*OrderService)
	if !ok {
		log.Printf("Failed to get order service")
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	var updatedOrder Order
	if err := c.BindJSON(&updatedOrder); err != nil {
		log.Printf("Failed to bind order: %v", err)
		c.AbortWithStatus(http.StatusBadRequest)
		return
	}

	// Update order status
	updatedOrder.Status = 2 // Completed

	err := client.repo.UpdateOrder(updatedOrder)
	if err != nil {
		log.Printf("Failed to update order %s: %s", updatedOrder.OrderID, err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	c.IndentedJSON(http.StatusOK, updatedOrder)
}
