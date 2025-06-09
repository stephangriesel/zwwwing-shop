# Dockerfile

# --- 1. Build Stage ---
# Use a Node.js base image

# Set the working directory
WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends build-essential python3

# Copy package files and install dependencies
COPY package.json package-lock.json* ./
RUN npm install

# Copy the rest of the application source code
COPY . .

# Build the Medusa project for production
RUN npm run build

# --- 2. Production Stage ---
# Use a smaller, more secure base image for the final product
FROM node:18-slim AS production

WORKDIR /app

# Copy only the necessary files from the build stage
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/dist ./dist
COPY --from=build /app/medusa-config.js ./medusa-config.js

# Expose the port Medusa runs on
EXPOSE 9000

# The command to run the Medusa server
CMD ["npm", "run", "start"]
```