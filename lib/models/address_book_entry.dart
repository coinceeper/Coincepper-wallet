/// مدل ورودی دفترچه آدرس
class AddressBookEntry {
  final String name;
  final String address;
  final String? blockchain;
  final String? note;

  AddressBookEntry({
    required this.name,
    required this.address,
    this.blockchain,
    this.note,
  });

  factory AddressBookEntry.fromJson(Map<String, dynamic> json) {
    return AddressBookEntry(
      name: json['name'] as String,
      address: json['address'] as String,
      blockchain: json['blockchain'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'address': address,
      'blockchain': blockchain,
      'note': note,
    };
  }

  @override
  String toString() {
    return 'AddressBookEntry(name: $name, address: $address, blockchain: $blockchain, note: $note)';
  }
} 