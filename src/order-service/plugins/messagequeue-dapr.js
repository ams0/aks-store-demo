"use strict"

const fp = require("fastify-plugin")

module.exports = fp(async function (fastify, opts) {
  fastify.decorate("sendMessage", async function (message) {
    const body = message.toString()

    // Check if we should use Dapr pub/sub
    if (process.env.USE_DAPR_PUBSUB === "true") {
      const pubsubName = process.env.PUBSUB_NAME || "order-pub-sub"
      const topic = process.env.PUBSUB_TOPIC || "orders"
      const daprPort = process.env.DAPR_HTTP_PORT || "3500"

      console.log(
        `Sending message via Dapr pub/sub: ${body} to topic ${topic} on pubsub ${pubsubName}`
      )

      try {
        // Use Dapr HTTP API to publish message
        const axios = require("axios")
        const response = await axios.post(
          `http://localhost:${daprPort}/v1.0/publish/${pubsubName}/${topic}`,
          JSON.parse(body), // Parse the JSON body for proper publishing
          {
            headers: {
              "Content-Type": "application/json",
            },
          }
        )

        console.log(`Message published successfully via Dapr: ${response.status}`)
      } catch (error) {
        console.error("Failed to publish message via Dapr:", error.message)
        throw error
      }
    } else if (process.env.ORDER_QUEUE_USERNAME && process.env.ORDER_QUEUE_PASSWORD) {
      // Original RabbitMQ implementation
      console.log(
        `sending message ${body} to ${process.env.ORDER_QUEUE_NAME} on ${process.env.ORDER_QUEUE_HOSTNAME} using local auth credentials`
      )

      const rhea = require("rhea")
      const container = rhea.create_container()
      var amqp_message = container.message

      const connectOptions = {
        hostname: process.env.ORDER_QUEUE_HOSTNAME,
        host: process.env.ORDER_QUEUE_HOSTNAME,
        port: process.env.ORDER_QUEUE_PORT,
        username: process.env.ORDER_QUEUE_USERNAME,
        password: process.env.ORDER_QUEUE_PASSWORD,
        reconnect_limit: process.env.ORDER_QUEUE_RECONNECT_LIMIT || 0,
      }

      if (process.env.ORDER_QUEUE_TRANSPORT !== undefined) {
        connectOptions.transport = process.env.ORDER_QUEUE_TRANSPORT
      }

      const connection = container.connect(connectOptions)

      container.once("sendable", function (context) {
        const sender = context.sender
        sender.send({
          body: amqp_message.data_section(Buffer.from(body, "utf8")),
        })
        sender.close()
        connection.close()
      })

      connection.open_sender(process.env.ORDER_QUEUE_NAME)
    } else if (process.env.USE_WORKLOAD_IDENTITY_AUTH === "true") {
      // Azure Service Bus implementation (unchanged)
      const { ServiceBusClient } = require("@azure/service-bus")
      const { DefaultAzureCredential } = require("@azure/identity")

      const fullyQualifiedNamespace =
        process.env.ORDER_QUEUE_HOSTNAME || process.env.AZURE_SERVICEBUS_FULLYQUALIFIEDNAMESPACE

      console.log(
        `sending message ${body} to ${process.env.ORDER_QUEUE_NAME} on ${fullyQualifiedNamespace} using Microsoft Entra ID Workload Identity credentials`
      )

      if (!fullyQualifiedNamespace) {
        console.log("no hostname set for message queue. exiting.")
        return
      }

      const queueName = process.env.ORDER_QUEUE_NAME

      const credential = new DefaultAzureCredential()

      async function sendMessage() {
        const sbClient = new ServiceBusClient(fullyQualifiedNamespace, credential)
        const sender = sbClient.createSender(queueName)

        try {
          await sender.sendMessages({ body: body })
        } finally {
          await sender.close()
          await sbClient.close()
        }
      }
      sendMessage().catch(console.error)
    } else {
      console.log("no credentials or Dapr configuration set for message queue. exiting.")
      return
    }
  })
})
