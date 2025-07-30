"use strict"

const fp = require("fastify-plugin")

// This plugin is disabled - messagequeue plugins are now self-conditional
module.exports = fp(async function (fastify, opts) {
  // No-op - plugins load themselves conditionally now
  console.log("messagequeue-loader.js: disabled (plugins are self-conditional)")
})
