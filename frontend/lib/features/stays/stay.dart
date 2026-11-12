class Stay {
  Stay({
    required this.id,
    this.propertySerialId = '',
    required this.title,
    required this.location,
    required this.notes,
    this.description = '',
    this.status = 'draft',
    this.setupMethod = 'manual',
    this.airbnbUrl,
    this.currentStep = 'property_type',
    this.propertyType = 'House',
    this.accommodationType = 'entireHouse',
    this.ownershipType = 'owner',
    this.address = const {},
    this.photos = const [],
    this.coverPhoto,
    this.documents = const [],
    this.guests = 2,
    this.bedrooms = 1,
    this.beds = 1,
    this.bathrooms = 1,
    this.amenities = const [],
    this.uniqueness = const [],
    this.experiences = const [],
    this.videoUrl,
    this.neighbourhood,
    this.basePrice = 0.0,
    this.checkIn,
    this.checkOut,
    this.houseRules = const {},
    this.instantBooking = true,
    this.cancellationPolicy = 'flexible',
    this.checkInMethod = 'host_greets',
    this.caretakerName = '',
    this.caretakerPhone = '',
    this.accountVerificationStatus = 'pending',
  });

  final int id;
  final String propertySerialId;
  final String title;
  final String location;
  final String notes;
  final String description;
  final String status;
  final String setupMethod;
  final String? airbnbUrl;
  final String currentStep;
  final String propertyType;
  final String accommodationType;
  final String ownershipType;
  final Map<String, dynamic> address;
  final List<String> photos;
  final String? coverPhoto;
  final List<String> documents;
  final int guests;
  final int bedrooms;
  final int beds;
  final int bathrooms;
  final List<String> amenities;
  final List<String> uniqueness;
  final List<String> experiences;
  final String? videoUrl;
  final String? neighbourhood;
  final double basePrice;
  final String? checkIn;
  final String? checkOut;
  final Map<String, dynamic> houseRules;
  final bool instantBooking;
  final String cancellationPolicy;
  final String checkInMethod;
  final String caretakerName;
  final String caretakerPhone;
  final String accountVerificationStatus;

  factory Stay.fromJson(Map<String, dynamic> json) {
    return Stay(
      id: (json['id'] as num?)?.toInt() ?? 0,
      propertySerialId: (json['property_serial_id'] as String?) ??
          (json['propertySerialId'] as String?) ??
          '',
      title: (json['title'] as String?) ?? '',
      location: (json['location'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'draft',
      setupMethod: (json['setup_method'] as String?) ?? 'manual',
      airbnbUrl: json['airbnb_url'] as String?,
      currentStep: (json['current_step'] as String?) ??
          (json['propertyCurrentStep'] as String?) ??
          'property_type',
      propertyType: (json['property_type'] as String?) ?? 'House',
      accommodationType:
          (json['accommodation_type'] as String?) ?? 'entireHouse',
      ownershipType: (json['ownership_type'] as String?) ?? 'owner',
      address: json['address'] is Map
          ? Map<String, dynamic>.from(json['address'] as Map)
          : {},
      photos: json['photos'] is List
          ? List<String>.from((json['photos'] as List).map((e) => e.toString()))
          : [],
      coverPhoto: json['cover_photo'] as String?,
      documents: json['documents'] is List
          ? List<String>.from(
              (json['documents'] as List).map((e) => e.toString()))
          : [],
      guests: (json['guests'] as num?)?.toInt() ?? 2,
      bedrooms: (json['bedrooms'] as num?)?.toInt() ?? 1,
      beds: (json['beds'] as num?)?.toInt() ?? 1,
      bathrooms: (json['bathrooms'] as num?)?.toInt() ?? 1,
      amenities: json['amenities'] is List
          ? List<String>.from(
              (json['amenities'] as List).map((e) => e.toString()))
          : [],
      uniqueness: json['uniqueness'] is List
          ? List<String>.from(
              (json['uniqueness'] as List).map((e) => e.toString()))
          : [],
      experiences: json['experiences'] is List
          ? List<String>.from(
              (json['experiences'] as List).map((e) => e.toString()))
          : [],
      videoUrl: json['video_url'] as String?,
      neighbourhood: json['neighbourhood'] as String?,
      basePrice: (json['base_price'] as num?)?.toDouble() ?? 0.0,
      checkIn: json['check_in'] as String?,
      checkOut: json['check_out'] as String?,
      houseRules: json['house_rules'] is Map
          ? Map<String, dynamic>.from(json['house_rules'] as Map)
          : {},
      instantBooking: (json['instant_booking'] as bool?) ?? true,
      cancellationPolicy:
          (json['cancellation_policy'] as String?) ?? 'flexible',
      checkInMethod: (json['check_in_method'] as String?) ?? 'host_greets',
      caretakerName: (json['caretaker_name'] as String?) ?? '',
      caretakerPhone: (json['caretaker_phone'] as String?) ?? '',
      accountVerificationStatus:
          (json['account_verification_status'] as String?) ?? 'pending',
    );
  }

  Map<String, dynamic> toPayload() => {
        'id': id,
        'property_serial_id': propertySerialId,
        'title': title,
        'location': location,
        'notes': notes,
        'description': description,
        'status': status,
        'setup_method': setupMethod,
        'airbnb_url': airbnbUrl,
        'current_step': currentStep,
        'property_type': propertyType,
        'accommodation_type': accommodationType,
        'ownership_type': ownershipType,
        'address': address,
        'photos': photos,
        'cover_photo': coverPhoto,
        'documents': documents,
        'guests': guests,
        'bedrooms': bedrooms,
        'beds': beds,
        'bathrooms': bathrooms,
        'amenities': amenities,
        'uniqueness': uniqueness,
        'experiences': experiences,
        'video_url': videoUrl,
        'neighbourhood': neighbourhood,
        'base_price': basePrice,
        'check_in': checkIn,
        'check_out': checkOut,
        'house_rules': houseRules,
        'instant_booking': instantBooking,
        'cancellation_policy': cancellationPolicy,
        'check_in_method': checkInMethod,
        'caretaker_name': caretakerName,
        'caretaker_phone': caretakerPhone,
        'account_verification_status': accountVerificationStatus,
      };

  Stay copyWith({
    int? id,
    String? propertySerialId,
    String? title,
    String? location,
    String? notes,
    String? description,
    String? status,
    String? setupMethod,
    String? airbnbUrl,
    String? currentStep,
    String? propertyType,
    String? accommodationType,
    String? ownershipType,
    Map<String, dynamic>? address,
    List<String>? photos,
    String? coverPhoto,
    List<String>? documents,
    int? guests,
    int? bedrooms,
    int? beds,
    int? bathrooms,
    List<String>? amenities,
    List<String>? uniqueness,
    List<String>? experiences,
    String? videoUrl,
    String? neighbourhood,
    double? basePrice,
    String? checkIn,
    String? checkOut,
    Map<String, dynamic>? houseRules,
    bool? instantBooking,
    String? cancellationPolicy,
    String? checkInMethod,
    String? caretakerName,
    String? caretakerPhone,
    String? accountVerificationStatus,
  }) {
    return Stay(
      id: id ?? this.id,
      propertySerialId: propertySerialId ?? this.propertySerialId,
      title: title ?? this.title,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      description: description ?? this.description,
      status: status ?? this.status,
      setupMethod: setupMethod ?? this.setupMethod,
      airbnbUrl: airbnbUrl ?? this.airbnbUrl,
      currentStep: currentStep ?? this.currentStep,
      propertyType: propertyType ?? this.propertyType,
      accommodationType: accommodationType ?? this.accommodationType,
      ownershipType: ownershipType ?? this.ownershipType,
      address: address ?? this.address,
      photos: photos ?? this.photos,
      coverPhoto: coverPhoto ?? this.coverPhoto,
      documents: documents ?? this.documents,
      guests: guests ?? this.guests,
      bedrooms: bedrooms ?? this.bedrooms,
      beds: beds ?? this.beds,
      bathrooms: bathrooms ?? this.bathrooms,
      amenities: amenities ?? this.amenities,
      uniqueness: uniqueness ?? this.uniqueness,
      experiences: experiences ?? this.experiences,
      videoUrl: videoUrl ?? this.videoUrl,
      neighbourhood: neighbourhood ?? this.neighbourhood,
      basePrice: basePrice ?? this.basePrice,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      houseRules: houseRules ?? this.houseRules,
      instantBooking: instantBooking ?? this.instantBooking,
      cancellationPolicy: cancellationPolicy ?? this.cancellationPolicy,
      checkInMethod: checkInMethod ?? this.checkInMethod,
      caretakerName: caretakerName ?? this.caretakerName,
      caretakerPhone: caretakerPhone ?? this.caretakerPhone,
      accountVerificationStatus:
          accountVerificationStatus ?? this.accountVerificationStatus,
    );
  }
}

