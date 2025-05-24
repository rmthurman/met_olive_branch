FROM mcr.microsoft.com/azureml/promptflow/promptflow-runtime:latest

#Install ODBC Driver for SQL Server
# Get signing key for repository from Microsoft
RUN  curl https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
# Obtain the configuration for the repositories and add it to the system.
RUN curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
# Update package lists
RUN sudo apt update
# Install MSSQL ODBC driver version 18
RUN sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18

# Install ODBC PostgreSQL driver
RUN apt-get update && apt-get install -y \
    unixodbc \
    unixodbc-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
COPY requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip && \
    pip install -r /tmp/requirements.txt

# Clean /etc/odbcinst.ini
RUN echo "" > /etc/odbcinst.ini

# Update /etc/odbcinst.ini
RUN echo "[ODBC Driver 18 for SQL Server]" >> /etc/odbcinst.ini && \
    echo "Description=Microsoft ODBC Driver 18 for SQL Server" >> /etc/odbcinst.ini && \
    echo "Driver=/opt/microsoft/msodbcsql18/lib64/libmsodbcsql-18.5.so.1.1" >> /etc/odbcinst.ini \
    echo "UsageCount=1" >> /etc/odbcinst.ini && 
