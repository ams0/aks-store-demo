package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

// Valid database API types
const (
	AZURE_COSMOS_DB_SQL_API = "cosmosdbsql"
)

// Dapr subscription structure
type Subscription struct {
	PubsubName string `json:"pubsubname"`
	Topic      string `json:"topic"`
	Route      string `json:"route"`
}

// Dapr CloudEvent structure for incoming messages
type CloudEvent struct {
	ID              string      `json:"id"`
	Source          string      `json:"source"`
	SpecVersion     string      `json:"specversion"`
	Type            string      `json:"type"`
	DataContentType string      `json:"datacontenttype"`
	Data            interface{} `json:"data"`
	Subject         string      `json:"subject,omitempty"`
	Time            string      `json:"time,omitempty"`
}

func main() {
	var orderService *OrderService

	// Check if we should use Dapr
	useDaprPubSub := os.Getenv("USE_DAPR_PUBSUB") == "true"
	useDaprStateStore := os.Getenv("USE_DAPR_STATE_STORE") == "true"

	log.Printf("Dapr pub/sub enabled: %v", useDaprPubSub)
	log.Printf("Dapr state store enabled: %v", useDaprStateStore)

	if useDaprStateStore {
		// Initialize Dapr-based order service
		orderService = &OrderService{
			repo: &DaprStateRepository{
				stateStoreName: os.Getenv("STATE_STORE_NAME"),
				daprPort:       os.Getenv("DAPR_HTTP_PORT"),
			},
		}
		log.Printf("Using Dapr state store: %s", os.Getenv("STATE_STORE_NAME"))
	} else {
		// Get the database API type for traditional approach
		apiType := os.Getenv("ORDER_DB_API")
		switch apiType {
		case "cosmosdbsql":
			log.Printf("Using Azure CosmosDB SQL API")
		default:
			log.Printf("Using MongoDB API")
		}

		// Initialize the traditional database
		var err error
		orderService, err = initDatabase(apiType)
		if err != nil {
			log.Printf("Failed to initialize database: %s", err)
			os.Exit(1)
		}
	}

	router := gin.Default()
	router.Use(cors.Default())
	router.Use(OrderMiddleware(orderService))

	// Traditional API endpoints
	router.GET("/order/fetch", fetchOrders)
	router.GET("/order/:id", getOrder)
	router.PUT("/order", updateOrder)
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"version": os.Getenv("APP_VERSION"),
		})
	})

	if useDaprPubSub {
		// Dapr subscription endpoint
		router.GET("/dapr/subscribe", getSubscriptions)
		// Dapr message handler endpoint
		router.POST("/orders", handleDaprOrder)
		log.Printf("Dapr pub/sub endpoints registered")
	}

	router.Run(":3001")
}

// Dapr subscription metadata endpoint
func getSubscriptions(c *gin.Context) {
	pubsubName := os.Getenv("PUBSUB_NAME")
	topic := os.Getenv("PUBSUB_TOPIC")

	if pubsubName == "" {
		pubsubName = "order-pub-sub"
	}
	if topic == "" {
		topic = "orders"
	}

	subscriptions := []Subscription{
		{
			PubsubName: pubsubName,
			Topic:      topic,
			Route:      "/orders",
		},
	}

	c.JSON(http.StatusOK, subscriptions)
}

// Dapr message handler for incoming orders
func handleDaprOrder(c *gin.Context) {
	client, ok := c.MustGet("orderService").(*OrderService)
	if !ok {
		log.Printf("Failed to get order service")
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	var cloudEvent CloudEvent
	if err := c.ShouldBindJSON(&cloudEvent); err != nil {
		log.Printf("Failed to bind CloudEvent: %v", err)
		c.AbortWithStatus(http.StatusBadRequest)
		return
	}

	log.Printf("Received order via Dapr pub/sub: %+v", cloudEvent)

	// Extract order data from CloudEvent
	orderData, err := json.Marshal(cloudEvent.Data)
	if err != nil {
		log.Printf("Failed to marshal order data: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	// Unmarshal into Order struct
	order, err := unmarshalOrderFromQueue(orderData)
	if err != nil {
		log.Printf("Failed to unmarshal order: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	// Save order to database/state store
	orders := []Order{order}
	err = client.repo.InsertOrders(orders)
	if err != nil {
		log.Printf("Failed to save order: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	log.Printf("Order %s processed successfully via Dapr", order.OrderID)

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

// Fetches orders - works with both traditional queue and Dapr
func fetchOrders(c *gin.Context) {
	client, ok := c.MustGet("orderService").(*OrderService)
	if !ok {
		log.Printf("Failed to get order service")
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	useDaprPubSub := os.Getenv("USE_DAPR_PUBSUB") == "true"

	if !useDaprPubSub {
		// Traditional queue-based approach
		orders, err := getOrdersFromQueue()
		if err != nil {
			log.Printf("Failed to fetch orders from queue: %s", err)
			c.AbortWithStatus(http.StatusInternalServerError)
			return
		}

		// Save orders to database
		err = client.repo.InsertOrders(orders)
		if err != nil {
			log.Printf("Failed to save orders to database: %s", err)
			c.AbortWithStatus(http.StatusInternalServerError)
			return
		}
	}

	// Return the orders to be processed (works for both approaches)
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

// DaprStateRepository implements OrderRepository using Dapr State API
type DaprStateRepository struct {
	stateStoreName string
	daprPort       string
}

func (r *DaprStateRepository) InsertOrders(orders []Order) error {
	if r.daprPort == "" {
		r.daprPort = "3500"
	}

	for _, order := range orders {
		// Create state request
		stateData := map[string]interface{}{
			"key":   order.OrderID,
			"value": order,
		}

		jsonData, err := json.Marshal([]map[string]interface{}{stateData})
		if err != nil {
			return fmt.Errorf("failed to marshal state data: %v", err)
		}

		// Send to Dapr state store
		url := fmt.Sprintf("http://localhost:%s/v1.0/state/%s", r.daprPort, r.stateStoreName)
		resp, err := http.Post(url, "application/json", bytes.NewBuffer(jsonData))
		if err != nil {
			return fmt.Errorf("failed to save order to Dapr state store: %v", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusNoContent {
			body, _ := io.ReadAll(resp.Body)
			return fmt.Errorf("Dapr state store returned error: %s", string(body))
		}

		log.Printf("Order %s saved to Dapr state store", order.OrderID)
	}

	return nil
}

func (r *DaprStateRepository) GetPendingOrders() ([]Order, error) {
	// Note: This is a simplified implementation
	// In practice, you'd need to implement a query mechanism or maintain an index
	// For demo purposes, we'll return an empty slice as orders are processed via pub/sub
	return []Order{}, nil
}

func (r *DaprStateRepository) GetOrder(orderID string) (*Order, error) {
	if r.daprPort == "" {
		r.daprPort = "3500"
	}

	url := fmt.Sprintf("http://localhost:%s/v1.0/state/%s/%s", r.daprPort, r.stateStoreName, orderID)
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to get order from Dapr state store: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("order not found")
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("Dapr state store returned error: %s", string(body))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %v", err)
	}

	var order Order
	if err := json.Unmarshal(body, &order); err != nil {
		return nil, fmt.Errorf("failed to unmarshal order: %v", err)
	}

	return &order, nil
}

func (r *DaprStateRepository) UpdateOrder(order Order) error {
	if r.daprPort == "" {
		r.daprPort = "3500"
	}

	// Create state request
	stateData := map[string]interface{}{
		"key":   order.OrderID,
		"value": order,
	}

	jsonData, err := json.Marshal([]map[string]interface{}{stateData})
	if err != nil {
		return fmt.Errorf("failed to marshal state data: %v", err)
	}

	// Send to Dapr state store
	url := fmt.Sprintf("http://localhost:%s/v1.0/state/%s", r.daprPort, r.stateStoreName)
	resp, err := http.Post(url, "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to update order in Dapr state store: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("Dapr state store returned error: %s", string(body))
	}

	log.Printf("Order %s updated in Dapr state store", order.OrderID)
	return nil
}
