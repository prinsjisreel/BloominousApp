import 'package:flutter/material.dart';

class Flower {
  final String id;
  final String name;
  final double price;
  final Color color;
  final String imageUrl;

  Flower({
    required this.id,
    required this.name,
    required this.price,
    required this.color,
    required this.imageUrl,
  });
}

final List<Flower> FLOWERS = [
  Flower(
    id: 'rose', 
    name: 'Red Rose', 
    price: 80.0, 
    color: Colors.red, 
    // Corrected: High-quality Red Rose
    imageUrl: 'https://images.unsplash.com/photo-1596073419667-9d77d59f033f?q=80&w=400&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D'
  ),
  Flower(
    id: 'sunflower', 
    name: 'Sunflower', 
    price: 150.0, 
    color: Colors.yellow, 
    // Verified: Sunflower field
    imageUrl: 'https://images.unsplash.com/photo-1470509037663-253afd7f0f51?w=400'
  ),
  Flower(
    id: 'lily', 
    name: 'White Lily', 
    price: 250.0, 
    color: Colors.white, 
    // Corrected: Actual White Lily (not a daisy)
    imageUrl: 'https://images.unsplash.com/photo-1674784708705-4667d407cc65?q=80&w=400&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D'
  ),
  Flower(
    id: 'peony', 
    name: 'Peony', 
    price: 800.0, 
    color: Colors.pinkAccent, 
    // Corrected: Lush Pink Peony
    imageUrl: 'https://images.unsplash.com/photo-1557926005-012bd4382a0d?q=80&w=400&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D'
  ),
];




