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

# Build the Medusa project. This will create the ".medusa/server" folder.
RUN npm run build


# =================================================================
# --- 2. Production Stage ---
# This is the final, lean image that will be deployed.
# =================================================================
FROM node:20-slim

WORKDIR /app

# Copy the built application from the correct output folder.
COPY --from=build /app/.medusa/server ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
# Copy the compiled config file from the correct output folder.
COPY --from=build /app/.medusa/server/medusa-config.js ./medusa-config.js

# Add the tsconfig.json file. The Medusa server needs this at runtime
# to resolve custom path aliases (e.g., @/services).
COPY --from=build /app/tsconfig.json ./tsconfig.json
# -----------------------

# Expose the port Medusa runs on (default is 9000)
EXPOSE 9000

# The command to start the Medusa server in production mode
CMD ["sh", "-c", "medusa migrations run && medusa start"]