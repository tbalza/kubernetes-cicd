# Use an official Alpine image as a parent image
FROM alpine:latest

# Install gettext which includes envsubst, and place it in /usr/local/bin
RUN apk add --no-cache gettext && ln -s /usr/bin/envsubst /usr/local/bin/envsubst

# Set the user to non-root for security
RUN adduser -D customuser
USER customuser

# Set the working directory to /usr/local/bin for convenience
WORKDIR /usr/local/bin

# Keep the container running with a simple command
CMD ["tail", "-f", "/dev/null"]