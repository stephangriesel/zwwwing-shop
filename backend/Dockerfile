# Dockerfile for a Medusa.js Project

# =================================================================
# --- 1. Build Stage ---
# Name this stage "build". We'll use it to install all dependencies
# and create the production build artifacts.
# =================================================================
FROM node:20-slim AS build

# Set the working directory
WORKDIR /app

# Copy package files.
COPY package.json package-lock.json* ./
RUN npm install --legacy-peer-deps

# Copy the rest of the application source code
COPY . .

# Build the Medusa project for production. This creates the 'dist' folder
# and compiles all .ts files into .js files inside 'dist'.
RUN npm run build


# =================================================================
# --- 2. Production Stage ---
# This is the final, lean image that will be deployed.
# =================================================================
FROM node:20-slim

WORKDIR /app

# Copy the built application and production dependencies from the "build" stage
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/dist/medusa-config.js ./medusa-config.js

# Expose the port Medusa runs on (default is 9000)
EXPOSE 9000

# The command to start the Medusa server in production mode
CMD ["npm", "run", "start"]