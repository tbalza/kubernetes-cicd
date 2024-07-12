# Use Alpine Linux as the base image for its small size
FROM alpine:latest

# Install gettext package (includes envsubst)
RUN apk add --no-cache gettext

# Set the working directory to /usr/local/bin
WORKDIR /usr/local/bin

# Copy the envsubst binary to the working directory to make it easier to reference
RUN cp /usr/bin/envsubst .

# Set the entry point to the envsubst binary
# This is optional, only set this if you intend to run the container as an executable
# ENTRYPOINT ["envsubst"]

# Set a default command that does nothing, keeping the container alive
CMD ["tail", "-f", "/dev/null"]