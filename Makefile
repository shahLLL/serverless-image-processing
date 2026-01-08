all: help
help:
	@echo "Use make init to initialize project"
	@echo "Use make run to update lambda source code"
	@echo "Use make plan to see planned changes"
	@echo "Use make deploy to deploy desired infrastructure"
	@echo "Use make destroy to remove infrastructure"
init: ./iac/terraform.tf
	cd ./iac && terraform init
run: ./src/lambda_function.py
	cd ./src && zip lambda_function.zip lambda_function.py && mv ./lambda_function.zip ../iac/
plan: ./iac/locals.tf ./iac/main.tf ./iac/outputs.tf ./iac/terraform.tf ./iac/variables.tf
	cd ./iac && terraform plan
deploy: ./iac/locals.tf ./iac/main.tf ./iac/outputs.tf ./iac/terraform.tf ./iac/variables.tf
	cd ./iac && terraform apply
destroy: ./iac/locals.tf ./iac/main.tf ./iac/outputs.tf ./iac/terraform.tf ./iac/variables.tf
	cd ./iac && terraform destroy