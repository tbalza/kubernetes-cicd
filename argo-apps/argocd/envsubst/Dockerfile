# Start from the Alpine Linux base image
FROM alpine:latest

# Install the gettext package which includes envsubst
RUN apk add --no-cache gettext

# Add a non-root user with UID 999
RUN adduser -D nonrootuser

# Create a directory for custom tools
RUN mkdir /custom-tools

# Copy the envsubst binary to the custom-tools directory
# Optionally, create a symbolic link instead of copying to retain original paths
RUN cp /usr/bin/envsubst /custom-tools/envsubst

# Set the user to nonrootuser to ensure non-root execution
USER nonrootuser

# Set the default work directory
WORKDIR /custom-tools

# Keep the container running with a simple command
CMD ["tail", "-f", "/dev/null"]