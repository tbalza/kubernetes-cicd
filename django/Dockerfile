# Use the official Python image as a base image
FROM python:3.12-slim

# Set environment variables to prevent Python from writing pyc files to disc (optional)
ENV PYTHONDONTWRITEBYTECODE 1
# Prevent Python from buffering stdout and stderr
ENV PYTHONUNBUFFERED 1

# Set the working directory in the container
WORKDIR /app

# Optional: Clearing the directory to avoid conflicts
RUN rm -rf /app/*

# Install Django
COPY requirements.txt /app/
RUN pip install --upgrade pip && pip install -r requirements.txt

# Copy the current directory contents into the container at /app
COPY . /app

# Make port 8000 available to the world outside this container
EXPOSE 8000

# Define the command to run your app using the Django development server
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
