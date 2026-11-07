class Stay {
  Stay({
    required this.id,
    required this.title,
    required this.location,
    required this.notes,
    this.checkIn,
    this.checkOut,
  });

  final int id;
  final String title;
  final String location;
  final String notes;
  final String? checkIn;
  final String? checkOut;

  factory Stay.fromJson(Map<String, dynamic> json) {
    return Stay(
      id: json['id'] as int,
      title: json['title'] as String,
      location: json['location'] as String,
      notes: (json['notes'] as String?) ?? '',
      checkIn: json['check_in'] as String?,
      checkOut: json['check_out'] as String?,
    );
  }

  Map<String, dynamic> toPayload() => {
        'title': title,
        'location': location,
        'notes': notes,
        'check_in': checkIn,
        'check_out': checkOut,
      };
}
