package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
)

// DaprStateRepository implements OrderRepo using Dapr State API
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

func (r *DaprStateRepository) GetOrder(orderID string) (Order, error) {
	if r.daprPort == "" {
		r.daprPort = "3500"
	}

	url := fmt.Sprintf("http://localhost:%s/v1.0/state/%s/%s", r.daprPort, r.stateStoreName, orderID)
	resp, err := http.Get(url)
	if err != nil {
		return Order{}, fmt.Errorf("failed to get order from Dapr state store: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return Order{}, fmt.Errorf("order not found")
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return Order{}, fmt.Errorf("Dapr state store returned error: %s", string(body))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return Order{}, fmt.Errorf("failed to read response body: %v", err)
	}

	var order Order
	if err := json.Unmarshal(body, &order); err != nil {
		return Order{}, fmt.Errorf("failed to unmarshal order: %v", err)
	}

	return order, nil
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
