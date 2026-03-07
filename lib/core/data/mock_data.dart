// Modelo de Serviço
class ServiceItem {
  final String name;
  final double price;
  final int durationMinutes;

  ServiceItem(
      {required this.name, required this.price, required this.durationMinutes});
}

// Modelo de Negócio (Atualizado com Serviços)
class Business {
  final String id;
  final String name;
  final String category;
  final String address;
  final double rating;
  final String imageUrl;
  final List<ServiceItem> services; // Lista de serviços da loja

  Business({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.rating,
    required this.imageUrl,
    required this.services,
  });
}

// DADOS SIMULADOS
final List<Business> mockBusinesses = [
  Business(
    id: '1',
    name: 'Barbearia Viking',
    category: 'Barbearia',
    address: 'Av. Paulista, 1000 - Centro',
    rating: 4.8,
    imageUrl:
        'https://img.freepik.com/fotos-gratis/homem-no-salao-de-barbearia-fazendo-o-corte-de-cabelo-e-barba_1303-20953.jpg',
    services: [
      ServiceItem(name: "Corte Degradê", price: 35.0, durationMinutes: 40),
      ServiceItem(name: "Barba Lenhador", price: 25.0, durationMinutes: 30),
      ServiceItem(
          name: "Combo (Cabelo + Barba)", price: 50.0, durationMinutes: 60),
      ServiceItem(name: "Sobrancelha", price: 10.0, durationMinutes: 15),
    ],
  ),
  Business(
    id: '2',
    name: 'Espaço Bella',
    category: 'Salão de Beleza',
    address: 'Rua das Flores, 200 - Jardins',
    rating: 4.9,
    imageUrl:
        'https://img.freepik.com/fotos-gratis/cabeleireiro-cortando-cabelo-de-mulher_23-2148992688.jpg',
    services: [
      ServiceItem(name: "Corte Feminino", price: 80.0, durationMinutes: 60),
      ServiceItem(name: "Escova Modeladora", price: 45.0, durationMinutes: 40),
      ServiceItem(
          name: "Hidratação Profunda", price: 120.0, durationMinutes: 90),
    ],
  ),
  Business(
    id: '3',
    name: 'Studio Nails',
    category: 'Manicure',
    address: 'Rua Augusta, 500 - Centro',
    rating: 4.5,
    imageUrl:
        'https://img.freepik.com/fotos-gratis/manicure-aplicando-esmalte-vermelho-nas-unhas-da-cliente_23-2148003666.jpg',
    services: [
      ServiceItem(name: "Mão Simples", price: 25.0, durationMinutes: 30),
      ServiceItem(name: "Pé Simples", price: 25.0, durationMinutes: 30),
      ServiceItem(name: "Mão + Pé", price: 45.0, durationMinutes: 60),
      ServiceItem(name: "Alongamento Gel", price: 150.0, durationMinutes: 120),
    ],
  ),
];
