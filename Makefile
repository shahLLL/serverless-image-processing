all: help
help:
	@printf "🔵 Use \e[1;34m%-14s\e[0m to \e[1;34m💻 Initialize Project\e[0m\n" "make init"
	@printf "⚪️ Use \e[1;34m%-14s\e[0m to \e[1;34m📝 Update Lambda Source Code\e[0m\n" "make update"
	@printf "🔵 Use \e[1;34m%-14s\e[0m to \e[1;34m🧼 Lint Terraform Configuration\e[0m\n" "make lint"
	@printf "⚪️ Use \e[1;34m%-14s\e[0m to \e[1;34m👀 See Planned Changes\e[0m\n" "make plan"
	@printf "🔵 Use \e[1;34m%-14s\e[0m to \e[1;34m🚀 Deploy Desired Infrastructure\e[0m\n" "make deploy"
	@printf "⚪️ Use \e[1;34m%-14s\e[0m to \e[1;34m🧨 Remove Infrastructure\e[0m\n" "make destroy"
	@printf "🔵 Use \e[1;34m%-14s\e[0m to \e[1;34m💻 Set Up the 🐍Python Source Environment\e[0m\n" "make src-init"
	@printf "⚪️ Use \e[1;34m%-14s\e[0m to \e[1;34m🧼 Lint the 🐍Python Source Code\e[0m\n" "make src-lint"
	@printf "🔵 Use \e[1;34m%-14s\e[0m to \e[1;34m🧪 Run the 🐍Python Unit Tests\e[0m\n" "make src-test"
	@printf "⚪️ Use \e[1;34m%-14s\e[0m to \e[1;34m🧱 Build the 🐍Python Source\e[0m\n" "make src-build"



init: ./iac/terraform.tf
	cd ./iac && terraform init
update: ./src/lambda_function.py
	cd ./src && zip lambda_function.zip lambda_function.py && mv ./lambda_function.zip ../iac/
fmt: ./iac/locals.tf ./iac/main.tf ./iac/outputs.tf ./iac/terraform.tf ./iac/variables.tf
	cd ./iac && terraform fmt -recursive
lint: fmt init ./iac/locals.tf ./iac/main.tf ./iac/outputs.tf ./iac/terraform.tf ./iac/variables.tf ./iac/.tflint.hcl
	cd ./iac && tflint --init && tflint && echo "✅ TFLint check passed successfully."
plan: ./iac/locals.tf ./iac/main.tf ./iac/outputs.tf ./iac/terraform.tf ./iac/variables.tf
	cd ./iac && terraform plan
deploy: ./iac/locals.tf ./iac/main.tf ./iac/outputs.tf ./iac/terraform.tf ./iac/variables.tf
	cd ./iac && terraform apply
destroy: ./iac/locals.tf ./iac/main.tf ./iac/outputs.tf ./iac/terraform.tf ./iac/variables.tf
	cd ./iac && terraform destroy
src-init: ./src/setup_venv.sh ./src/requirements.txt
	cd ./src && ./setup_venv.sh
src-lint: ./src/.flake8 ./src/lambda_function.py ./src/tests/test_lambda_function.py ./src/.venv
	cd ./src && . .venv/bin/activate && flake8 . && echo "✅ Python Source Code Linting Successful"
src-test: ./src/.venv ./src/lambda_function.py ./src/tests/test_lambda_function.py
	cd ./src && . .venv/bin/activate && pytest -q
src-build: src-init src-lint src-test
	@echo "✅ Source Code Build Successful"
