# Pull the image
Run `docker pull nakanomiku/mart:v1.1`

# Run the container
Run `docker run -ti -d -v <workdir>:/riscv/workspace nakanomiku/mart:v1.1`

# Build the image
1. Create an empty directory 
2. Put MART.zip and this Dockerfile under this directory
3. Run `docker build -t <image_name>:<version> .` under this directory


