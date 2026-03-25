path_model = 'c:/src/MarkaAI/lib/core/models/shop_model.dart'
path_login = 'c:/src/MarkaAI/lib/modules/login/login_page.dart'

print("Substituindo 'owner_email' por 'email'...")

# 1. Ajustar shop_model.dart
with open(path_model, 'r', encoding='utf-8') as f:
    model = f.read()

model = model.replace("map['owner_email']", "map['email']")
model = model.replace("'owner_email': ownerEmail", "'email': ownerEmail")

with open(path_model, 'w', encoding='utf-8') as f:
    f.write(model)
print("shop_model.dart atualizado.")

# 2. Ajustar login_page.dart
with open(path_login, 'r', encoding='utf-8') as f:
    login = f.read()

login = login.replace("'owner_email': _emailCtrl.text.trim()", "'email': _emailCtrl.text.trim()")

with open(path_login, 'w', encoding='utf-8') as f:
    f.write(login)
print("login_page.dart atualizado.")

print("Substituição concluída!")
