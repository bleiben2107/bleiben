import 'package:flutter/material.dart';
import 'package:bleiben/core/theme/app_theme.dart';
import 'package:bleiben/core/theme/app_fonts.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';
import '../home/home_content.dart';
import '../home/home_overlays.dart';
import '../home/home_sections.dart' show BleibenWordmark;
import 'stay.dart';
import 'stays_controller.dart';

class AddPropertyWizardScreen extends StatefulWidget {
  const AddPropertyWizardScreen({
    super.key,
    this.stays,
    this.api,
    this.initialDraft,
    this.onSave,
  });

  final StaysController? stays;
  final ApiClient? api;
  final Stay? initialDraft;
  final ValueChanged<Stay>? onSave;

  @override
  State<AddPropertyWizardScreen> createState() =>
      _AddPropertyWizardScreenState();
}

class _AddPropertyWizardScreenState extends State<AddPropertyWizardScreen> {
  // Brand color from Figma designs
  static const Color figmaCoral = AppTheme.forest;

  // ═══════════════════════════════════════════════════════════════════════════
  // THE 19 STEPS OF THE PROPERTY LISTING WIZARD (06-property-listing-wizard.md)
  // 0: Start Page (Import Airbnb / Create Manually / Clone) [Figma 6:2]
  // 1: Property Type (21 types) [Figma 11:110]
  // 2: Accommodation Type (Entire / Private / Shared) [Figma 15:2]
  // 3: Ownership (Owner vs Manager)
  // 4: Property Address & Map Pin [Figma 17:139]
  // 5: Photos (>=10 photos)
  // 6: Documents & Property Proof
  // 7: Floor Plan & Capacity (Guests, Beds, Bedrooms, Baths)
  // 8: Detailed Amenities
  // 9: Uniqueness Tags (Views, Vibes, Pools - up to 4)
  // 10: Experiences Offered (up to 4)
  // 11: Property Title & Description
  // 12: Neighbourhood Details
  // 13: Base Price Per Night
  // 14: Check-in & Check-out Times
  // 15: House Rules, Instant Booking & Cancellation Policy
  // 16: Check-in Method & Caretaker
  // 17: Account & Identity Verification (Live QR App screen)
  // 18: Listing Preview
  // 19: Publish Property & Setup Call
  // ═══════════════════════════════════════════════════════════════════════════
  int _currentStep = 0;
  final int _totalSteps = 20;

  // Step 0: Method
  String _setupMethod = 'manual';
  final _airbnbUrlController = TextEditingController();

  // Step 1: Property Type
  String _propertyType = 'House';

  // Step 2: Accommodation Type
  String _accommodationType = 'entireHouse';

  // Step 3: Ownership
  String _ownershipType = 'owner'; // 'owner' | 'manager'

  // Step 4: Address & Location
  final _locationController = TextEditingController();
  final _streetController = TextEditingController();
  final _aptController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _countryController = TextEditingController();

  // Step 5: Photos (>=10 recommended)
  final List<String> _photos = [];
  String? _coverPhoto;

  // Step 6: Documents
  final List<String> _documents = [];

  // Step 7: Capacity
  int _guests = 1;
  int _bedrooms = 1;
  int _beds = 1;
  int _bathrooms = 1;

  // Step 8: Amenities
  final Set<String> _selectedAmenities = {};

  // Step 9: Uniqueness (up to 4)
  final Set<String> _selectedUniqueness = {};

  // Step 10: Experiences (up to 4)
  final Set<String> _selectedExperiences = {};

  // Step 11: Title & Description
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _videoUrlController = TextEditingController();

  // Step 12: Neighbourhood
  final _neighbourhoodController = TextEditingController();

  // Step 13: Price
  final _priceController = TextEditingController();

  // Step 14: Check-in / check-out times
  final _checkInController = TextEditingController();
  final _checkOutController = TextEditingController();

  // Step 15: House Rules & Policies
  bool _childFriendly = true;
  bool _infantFriendly = true;
  bool _petsAllowed = false;
  bool _smokingAllowed = false;
  bool _partiesAllowed = false;
  final _additionalRulesController = TextEditingController();
  bool _instantBooking = true;
  String _cancellationPolicy = 'flexible'; // 'flexible' | 'moderate'

  // Step 16: Check-in Method & Caretaker
  String _checkInMethod = 'host_greets'; // 'host_greets' | 'keypad' | 'staff'
  final _caretakerNameController = TextEditingController();
  final _caretakerPhoneController = TextEditingController();

  // Step 17: ID Verification
  String _verificationStatus = 'pending';

  // Internal persistence state
  int _draftPropertyId = 0;
  String? _draftPropertySerialId;
  bool _isSaving = false;

  // The 21 Property Types from Figma node 11:110
  static const List<(String, IconData)> kPropertyTypes = [
    ('House', Icons.home_outlined),
    ('Villa', Icons.villa_outlined),
    ('Cottage', Icons.cottage_outlined),
    ('Apartment', Icons.apartment_outlined),
    ('Farm House', Icons.house_siding_rounded),
    ('Beach House', Icons.beach_access_outlined),
    ('Bed & Breakfast', Icons.free_breakfast_outlined),
    ('Boutique Hotels', Icons.hotel_outlined),
    ('Tree House', Icons.nature_people_outlined),
    ('Chalet', Icons.holiday_village_outlined),
    ('Glamping', Icons.cabin_outlined),
    ('Unique Stay', Icons.auto_awesome_outlined),
    ('Hut', Icons.terrain_outlined),
    ('Lodge', Icons.roofing_outlined),
    ('Dome', Icons.wb_twilight_outlined),
    ('Boat House', Icons.directions_boat_outlined),
    ('Campsite', Icons.fireplace_outlined),
    ('Destination Wedding', Icons.celebration_outlined),
    ('Tent', Icons.park_outlined),
    ('Cabin', Icons.forest_outlined),
    ('Castle', Icons.fort_outlined),
  ];

  StaysController? _effectiveStays;

  @override
  void initState() {
    super.initState();
    if (widget.stays != null) {
      _effectiveStays = widget.stays;
    } else if (widget.api != null) {
      _effectiveStays = StaysController(api: widget.api!);
    } else {
      _initFallbackController();
    }
    if (widget.initialDraft != null) {
      _loadFromDraft(widget.initialDraft!);
    }
  }

  Future<void> _initFallbackController() async {
    final session = SessionStore();
    await session.load();
    if (mounted && _effectiveStays == null) {
      setState(() {
        _effectiveStays = StaysController(api: ApiClient(session: session));
      });
    }
  }

  void _loadFromDraft(Stay draft) {
    _draftPropertyId = draft.id;
    _draftPropertySerialId = draft.propertySerialId;
    _titleController.text = draft.title;
    _locationController.text = draft.location;
    _descriptionController.text = draft.description;
    _propertyType = draft.propertyType;
    _accommodationType = draft.accommodationType;
    _ownershipType = draft.ownershipType;
    _guests = draft.guests;
    _bedrooms = draft.bedrooms;
    _beds = draft.beds;
    _bathrooms = draft.bathrooms;
    _priceController.text = draft.basePrice.toStringAsFixed(0);
    _checkInController.text = draft.checkIn ?? '';
    _checkOutController.text = draft.checkOut ?? '';
    _selectedAmenities.clear();
    _selectedAmenities.addAll(draft.amenities);
    _selectedUniqueness.clear();
    _selectedUniqueness.addAll(draft.uniqueness);
    _selectedExperiences.clear();
    _selectedExperiences.addAll(draft.experiences);
    _photos.clear();
    _photos.addAll(draft.photos);
    _coverPhoto = draft.coverPhoto;
    _cancellationPolicy = draft.cancellationPolicy;
    _checkInMethod = draft.checkInMethod;
    _caretakerNameController.text = draft.caretakerName;
    _caretakerPhoneController.text = draft.caretakerPhone;
    _verificationStatus = draft.accountVerificationStatus;
  }

  Stay _buildCurrentStay() {
    return Stay(
      id: _draftPropertyId,
      propertySerialId: _draftPropertySerialId ?? '',
      title: _titleController.text.trim(),
      location: _locationController.text.trim(),
      notes: _descriptionController.text.trim(),
      description: _descriptionController.text.trim(),
      setupMethod: _setupMethod,
      airbnbUrl:
          _setupMethod == 'airbnb' ? _airbnbUrlController.text.trim() : null,
      currentStep: _getStepCode(_currentStep),
      propertyType: _propertyType,
      accommodationType: _accommodationType,
      ownershipType: _ownershipType,
      address: {
        'formattedAddress': _locationController.text.trim(),
        'streetName': _streetController.text.trim(),
        'aptSuite': _aptController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),
        'postalCode': _postalCodeController.text.trim(),
        'country': _countryController.text.trim(),
      },
      photos: List<String>.from(_photos),
      coverPhoto: _coverPhoto ?? (_photos.isNotEmpty ? _photos.first : null),
      documents: List<String>.from(_documents),
      guests: _guests,
      bedrooms: _bedrooms,
      beds: _beds,
      bathrooms: _bathrooms,
      amenities: _selectedAmenities.toList(),
      uniqueness: _selectedUniqueness.toList(),
      experiences: _selectedExperiences.toList(),
      videoUrl: _videoUrlController.text.trim(),
      neighbourhood: _neighbourhoodController.text.trim(),
      basePrice: double.tryParse(_priceController.text) ?? 0.0,
      checkIn: _checkInController.text.trim(),
      checkOut: _checkOutController.text.trim(),
      houseRules: {
        'childFriendly': _childFriendly,
        'infantFriendly': _infantFriendly,
        'petsAllowed': _petsAllowed,
        'smokingAllowed': _smokingAllowed,
        'partiesAllowed': _partiesAllowed,
        'additionalRules': _additionalRulesController.text.trim(),
      },
      instantBooking: _instantBooking,
      cancellationPolicy: _cancellationPolicy,
      checkInMethod: _checkInMethod,
      caretakerName: _caretakerNameController.text.trim(),
      caretakerPhone: _caretakerPhoneController.text.trim(),
      accountVerificationStatus: _verificationStatus,
    );
  }

  String _getStepCode(int step) {
    switch (step) {
      case 0:
        return 'start';
      case 1:
        return 'property_type';
      case 2:
        return 'accommodation_type';
      case 3:
        return 'property_owner';
      case 4:
        return 'property_address';
      case 5:
        return 'property_photo';
      case 6:
        return 'property_proof';
      case 7:
        return 'about_property';
      case 8:
        return 'amenities';
      case 9:
        return 'unique_about_property';
      case 10:
        return 'property_experience';
      case 11:
        return 'property_title';
      case 12:
        return 'property_neighbourhood';
      case 13:
        return 'property_price';
      case 14:
        return 'check_in_out';
      case 15:
        return 'house_rules';
      case 16:
        return 'check_In_method';
      case 17:
        return 'account_verification';
      case 18:
        return 'property_preview';
      case 19:
        return 'publish_property';
      default:
        return 'property_type';
    }
  }

  Future<void> _persistStep() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final stay = _buildCurrentStay();

      if (_effectiveStays != null) {
        final success = await _effectiveStays!.save(stay);
        if (success && _effectiveStays!.currentDraft != null && mounted) {
          setState(() {
            _draftPropertyId = _effectiveStays!.currentDraft!.id;
            _draftPropertySerialId =
                _effectiveStays!.currentDraft!.propertySerialId;
          });
        } else if (!success && _effectiveStays!.error != null) {}
      } else if (widget.onSave != null) {
        widget.onSave!(stay);
      }
    } catch (e) {
      debugPrint('❌ [Wizard] Exception persisting step: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _airbnbUrlController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _videoUrlController.dispose();
    _neighbourhoodController.dispose();
    _locationController.dispose();
    _streetController.dispose();
    _aptController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    _priceController.dispose();
    _checkInController.dispose();
    _checkOutController.dispose();
    _additionalRulesController.dispose();
    _caretakerNameController.dispose();
    _caretakerPhoneController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NAVIGATION HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _next() async {
    if (_isSaving) return;

    if (_currentStep == 0) {
      if (_setupMethod == 'airbnb') {
        final url = _airbnbUrlController.text.trim();
        if (url.isEmpty) {
          _showError('Please paste your Airbnb listing link');
          return;
        }
        _titleController.text = 'Imported Airbnb Stay';
        _descriptionController.text =
            'Imported directly from Airbnb ($url). Ready for OTA multi-calendar sync.';
      } else if (_setupMethod == 'clone') {
        if (_titleController.text.isNotEmpty) {
          _titleController.text = '${_titleController.text} (Copy)';
        }
      }
      await _persistStep();
      if (mounted) setState(() => _currentStep = 1);
      return;
    }

    if (_currentStep == 1) {
      if (_propertyType.isEmpty) {
        _showError('Please select a property type');
        return;
      }
      await _persistStep();
      if (mounted) setState(() => _currentStep = 2);
      return;
    }

    if (_currentStep == 2) {
      if (_accommodationType.isEmpty) {
        _showError('Please select an option that describes your place');
        return;
      }
      await _persistStep();
      if (mounted) setState(() => _currentStep = 3);
      return;
    }

    if (_currentStep == 3) {
      await _persistStep();
      if (mounted) setState(() => _currentStep = 4);
      return;
    }

    if (_currentStep == 4) {
      await _persistStep();
      if (mounted) setState(() => _currentStep = 5);
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      await _persistStep();
      if (mounted) setState(() => _currentStep++);
    } else {
      await _publish();
    }
  }

  void _back() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  Future<void> _publish() async {
    setState(() => _isSaving = true);
    final stay = _buildCurrentStay();

    if (_effectiveStays != null && _draftPropertyId > 0) {
      await _effectiveStays!.publish(_draftPropertyId);
    } else if (widget.onSave != null) {
      widget.onSave!(stay.copyWith(status: 'activated'));
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppTheme.success, size: 28),
            const SizedBox(width: 10),
            Text('Listing Published!',
                style: AppFonts.sans(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Your property "${stay.title}" has been published! Our team will reach out to connect your OTAs and sync calendars.',
          style: AppFonts.sans(
              fontSize: 14.5, color: AppTheme.inkSoft),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: figmaCoral,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(stay);
            },
            child: Text('Go to Host Panel',
                style: AppFonts.sans(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD METHOD ROUTING ALL 20 STEPS
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: _buildCurrentStepWidget(),
    );
  }

  Widget _buildCurrentStepWidget() {
    switch (_currentStep) {
      case 0:
        return _buildStep0ExactFigma();
      case 1:
        return _buildStep1SelectPropertyTypeFigma();
      case 2:
        return _buildStep2PlaceTypeFigma();
      case 3:
        return _buildStep3OwnerManager();
      case 4:
        return _buildStep4AddressFigma();
      case 5:
        return _buildStep5Photos();
      case 6:
        return _buildStep6Documents();
      case 7:
        return _buildStep7Capacity();
      case 8:
        return _buildStep8Amenities();
      case 9:
        return _buildStep9Uniqueness();
      case 10:
        return _buildStep10Experiences();
      case 11:
        return _buildStep11TitleAndDescription();
      case 12:
        return _buildStep12Neighbourhood();
      case 13:
        return _buildStep13Pricing();
      case 14:
        return _buildStep14CheckInOut();
      case 15:
        return _buildStep15HouseRules();
      case 16:
        return _buildStep16CheckInMethod();
      case 17:
        return _buildStep17AccountVerification();
      case 18:
        return _buildStep18Preview();
      case 19:
        return _buildStep19Publish();
      default:
        return _buildStep0ExactFigma();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 0: FIGMA 6:2 - CHOOSE HOW TO ADD PROPERTY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep0ExactFigma() {
    return Column(
      children: [
        _buildFigmaMainHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 60),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: AppFonts.sans(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          color: AppTheme.ink,
                        ),
                        children: const [
                          TextSpan(text: 'Set up your property on '),
                          TextSpan(
                            text: 'Bleiben',
                            style: TextStyle(color: AppTheme.terra),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Text(
                        'Bleiben brings your direct bookings, Airbnb, Booking.com and other channels together in one calm place.',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.muted,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _buildFigmaSetupProgress(),
                    const SizedBox(height: 48),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'CHOOSE HOW TO ADD YOUR PROPERTY',
                        style: AppFonts.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth >= 780;
                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildCardAirbnb()),
                              const SizedBox(width: 20),
                              Expanded(child: _buildCardManual()),
                              const SizedBox(width: 20),
                              Expanded(child: _buildCardClone()),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              _buildCardAirbnb(),
                              const SizedBox(height: 14),
                              _buildCardManual(),
                              const SizedBox(height: 14),
                              _buildCardClone(),
                            ],
                          );
                        }
                      },
                    ),
                    if (_setupMethod == 'airbnb') ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.paper,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('Airbnb Listing Link'),
                            TextField(
                              controller: _airbnbUrlController,
                              decoration: _inputDecoration(
                                'https://www.airbnb.com/rooms/12345678',
                                prefixText: '🔗 ',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 38),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: figmaCoral,
                        minimumSize: const Size(260, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                        ),
                        elevation: 4,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text(
                              _getStep0ButtonText(),
                              style: AppFonts.sans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1: FIGMA 11:110 - SELECT PROPERTY TYPE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep1SelectPropertyTypeFigma() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Select your property type',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Text(
                        'Choose one primary type that best describes your place to help guests find you faster.',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.muted,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        int crossAxisCount = 5;
                        if (constraints.maxWidth < 640) {
                          crossAxisCount = 2;
                        } else if (constraints.maxWidth < 840) {
                          crossAxisCount = 3;
                        } else if (constraints.maxWidth < 1040) {
                          crossAxisCount = 4;
                        }

                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 1.15,
                          ),
                          itemCount: kPropertyTypes.length,
                          itemBuilder: (context, index) {
                            final (label, iconData) = kPropertyTypes[index];
                            final isSelected = _propertyType == label;

                            return InkWell(
                              onTap: () =>
                                  setState(() => _propertyType = label),
                              borderRadius: BorderRadius.circular(16),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.paper
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? figmaCoral
                                        : AppTheme.border,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isSelected
                                          ? figmaCoral.withOpacity(0.08)
                                          : AppTheme.ink.withValues(alpha: 0.03),
                                      blurRadius: isSelected ? 12 : 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      iconData,
                                      size: 32,
                                      color: isSelected
                                          ? figmaCoral
                                          : AppTheme.inkSoft,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      label,
                                      textAlign: TextAlign.center,
                                      style: AppFonts.sans(
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? figmaCoral
                                            : AppTheme.ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 1 / 19, backLabel: 'Cancel'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2: FIGMA 15:2 - ACCOMMODATION TYPE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep2PlaceTypeFigma() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Which of these best describes your place?',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Text(
                        'Choose the option that accurately defines guest privacy during their stay.',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.muted,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth >= 840;
                        final cards = [
                          _buildPlaceTypeCard(
                            id: 'entireHouse',
                            title: 'An entire place',
                            subtitle:
                                'Guests have the whole place to themselves. This usually includes a bedroom, a bathroom, and a kitchen.',
                            icon: Icons.home_outlined,
                            isSelected: _accommodationType == 'entireHouse',
                            onSelect: () => setState(
                                () => _accommodationType = 'entireHouse'),
                          ),
                          _buildPlaceTypeCard(
                            id: 'privateRoom',
                            title: 'A private room',
                            subtitle:
                                'Guests have their own private room for sleeping. Other areas could be shared.',
                            icon: Icons.meeting_room_outlined,
                            isSelected: _accommodationType == 'privateRoom',
                            onSelect: () => setState(
                                () => _accommodationType = 'privateRoom'),
                          ),
                          _buildPlaceTypeCard(
                            id: 'sharedRoom',
                            title: 'A shared room',
                            subtitle:
                                'Guests sleep in a bedroom or a common area that may be shared with others.',
                            icon: Icons.hotel_outlined,
                            isSelected: _accommodationType == 'sharedRoom',
                            onSelect: () => setState(
                                () => _accommodationType = 'sharedRoom'),
                          ),
                        ];

                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < cards.length; i++) ...[
                                if (i > 0) const SizedBox(width: 24),
                                Expanded(child: cards[i]),
                              ],
                            ],
                          );
                        } else {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < cards.length; i++) ...[
                                if (i > 0) const SizedBox(height: 20),
                                cards[i],
                              ],
                            ],
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 2 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 3: OWNER VS MANAGER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep3OwnerManager() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Are you the property owner or manager?',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Text(
                        'This helps us configure legal settlement ledgers, co-host permissions, and agreement documentation.',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSelectCard(
                            title: 'I am the Property Owner',
                            subtitle:
                                'I legally own the property and want to manage direct payouts and channel integrations.',
                            icon: Icons.person_outline_rounded,
                            isSelected: _ownershipType == 'owner',
                            onTap: () =>
                                setState(() => _ownershipType = 'owner'),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildSelectCard(
                            title: 'I am a Property Manager',
                            subtitle:
                                'I manage this homestay on behalf of the owner as a professional hospitality manager or co-host.',
                            icon: Icons.business_outlined,
                            isSelected: _ownershipType == 'manager',
                            onTap: () =>
                                setState(() => _ownershipType = 'manager'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 3 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 4: FIGMA 17:139 - ADDRESS & INTERACTIVE MAP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep4AddressFigma() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 44, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: const BoxDecoration(
                            color: figmaCoral,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            'Add your property address',
                            textAlign: TextAlign.center,
                            style: AppFonts.sans(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                              letterSpacing: -0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Text(
                        'Your address is only shared with guests after they’ve made a reservation.',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.muted,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth >= 600;
                        final mapHeight = isDesktop ? 440.0 : 340.0;

                        return Container(
                          width: double.infinity,
                          height: mapHeight,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: AppTheme.successSoft,
                            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                            border: Border.all(
                              color: AppTheme.border,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.ink.withValues(alpha: 0.04),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _FigmaMapPainter(),
                                ),
                              ),
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                AppTheme.ink.withValues(alpha: 0.12),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        _locationController.text
                                                .trim()
                                                .isNotEmpty
                                            ? _locationController.text.trim()
                                            : 'Your place location',
                                        style: AppFonts.sans(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.ink,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Icon(
                                      Icons.location_on_rounded,
                                      size: 44,
                                      color: AppTheme.forest,
                                    ),
                                    Container(
                                      width: 22,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: AppTheme.forest
                                            .withOpacity(0.28),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                top: 20,
                                left: 20,
                                right: 20,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 620),
                                    child: Container(
                                      height: 54,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                                        border: Border.all(
                                            color: AppTheme.border),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                AppTheme.ink.withValues(alpha: 0.08),
                                            blurRadius: 14,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on_rounded,
                                            color: AppTheme.inkSoft,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: TextField(
                                              controller: _locationController,
                                              style: AppFonts.sans(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.ink,
                                              ),
                                              decoration: InputDecoration(
                                                border: InputBorder.none,
                                                hintText: 'Enter Your Address',
                                                hintStyle: AppFonts.sans(
                                                  color:
                                                      AppTheme.hint,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                              onChanged: (_) => setState(() {}),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Use current location',
                                            icon: const Icon(
                                              Icons.my_location_rounded,
                                              size: 20,
                                              color: figmaCoral,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _locationController.text =
                                                    'Lonavala, Maharashtra';
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 18,
                                left: 18,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                                    border: Border.all(
                                        color: AppTheme.border),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        size: 16,
                                        color: AppTheme.success,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Pin placed accurately',
                                        style: AppFonts.sans(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _buildLocationPill('Lonavala, Maharashtra'),
                        _buildLocationPill('North Goa, Goa'),
                        _buildLocationPill('Alibaug, Maharashtra'),
                        _buildLocationPill('Manali, Himachal Pradesh'),
                        _buildLocationPill('Udaipur, Rajasthan'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 4 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 5: PHOTOS (>= 10 PHOTOS)
  // ═══════════════════════════════════════════════════════════════════════════

  void _addPhotoDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add Property Photo',
            style: AppFonts.sans(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Photo URL',
                hintText: 'https://example.com/property.jpg',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                controller.text =
                    'https://images.unsplash.com/photo-1580587771525-78b9dba3b914?w=800';
              },
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Insert Sample Photo'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                setState(() => _photos.add(url));
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: figmaCoral),
            child:
                const Text('Add Photo', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addDocumentDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add Property Document',
            style: AppFonts.sans(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Document Name or Link',
                hintText: 'e.g. Electricity_Bill_2024.pdf',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                controller.text = 'Property_Registration_Deed.pdf';
              },
              icon: const Icon(Icons.description, size: 16),
              label: const Text('Insert Sample: Deed.pdf'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final doc = controller.text.trim();
              if (doc.isNotEmpty) {
                setState(() => _documents.add(doc));
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: figmaCoral),
            child: const Text('Add Document',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildStep5Photos() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Upload your property photos',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'High-quality photos increase booking conversions by up to 40%. At least 10 photos recommended.',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                        fontSize: 15,
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 36),
                    InkWell(
                      onTap: _addPhotoDialog,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 140,
                        decoration: BoxDecoration(
                          color: AppTheme.paper,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppTheme.borderStrong,
                              style: BorderStyle.solid),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_photo_alternate_outlined,
                                  size: 40, color: figmaCoral),
                              const SizedBox(height: 8),
                              Text(
                                'Click to add photos or paste image URL',
                                style: AppFonts.sans(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.ink,
                                ),
                              ),
                              Text(
                                'PNG, JPG, WebP up to 5MB each',
                                style: AppFonts.sans(
                                    fontSize: 12,
                                    color: AppTheme.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_photos.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.paper,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Center(
                          child: Text(
                            'No photos added yet. Tap above to add.',
                            style: AppFonts.sans(
                                color: AppTheme.hint),
                          ),
                        ),
                      ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (int i = 0; i < _photos.length; i++)
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  _photos[i],
                                  width: 140,
                                  height: 100,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 140,
                                    height: 100,
                                    color: AppTheme.border,
                                    child: const Icon(Icons.image,
                                        color: AppTheme.muted),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: InkWell(
                                  onTap: () {
                                    setState(() => _photos.removeAt(i));
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppTheme.muted,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 5 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 6: DOCUMENTS & PROPERTY PROOF
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep6Documents() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: [
                    Text(
                      'Property ownership documents',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Upload utility bills, tax receipts, or registration deed for trust verification.',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 15, color: AppTheme.muted),
                    ),
                    const SizedBox(height: 36),
                    InkWell(
                      onTap: _addDocumentDialog,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: AppTheme.paper,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppTheme.borderStrong,
                              style: BorderStyle.solid),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.upload_file_rounded,
                                  size: 36, color: figmaCoral),
                              const SizedBox(height: 8),
                              Text(
                                'Click to add property documents or deed',
                                style: AppFonts.sans(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.ink,
                                ),
                              ),
                              Text(
                                'PDF, JPG, PNG up to 10MB',
                                style: AppFonts.sans(
                                    fontSize: 12,
                                    color: AppTheme.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_documents.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.paper,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Center(
                          child: Text(
                            'No documents uploaded yet (optional for drafting)',
                            style: AppFonts.sans(
                                color: AppTheme.hint),
                          ),
                        ),
                      ),
                    for (final doc in _documents)
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.paper,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.description_outlined,
                                color: figmaCoral),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(doc,
                                  style: AppFonts.sans(
                                      fontWeight: FontWeight.w600)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  size: 18, color: AppTheme.muted),
                              onPressed: () =>
                                  setState(() => _documents.remove(doc)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 6 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 7: FLOOR PLAN & CAPACITY (GUESTS, BEDS, ROOMS)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep7Capacity() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    Text(
                      'How many guests can stay here?',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Ensure your property has sufficient bedding and amenities for this capacity.',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 15, color: AppTheme.muted),
                    ),
                    const SizedBox(height: 40),
                    _buildCounterRow('Guests allowed', _guests,
                        (v) => setState(() => _guests = v.clamp(1, 50))),
                    const Divider(height: 36),
                    _buildCounterRow('Bedrooms', _bedrooms,
                        (v) => setState(() => _bedrooms = v.clamp(1, 25))),
                    const Divider(height: 36),
                    _buildCounterRow('Beds', _beds,
                        (v) => setState(() => _beds = v.clamp(1, 50))),
                    const Divider(height: 36),
                    _buildCounterRow('Bathrooms', _bathrooms,
                        (v) => setState(() => _bathrooms = v.clamp(1, 20))),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 7 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 8: AMENITIES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep8Amenities() {
    final list = [
      ('Wifi', Icons.wifi_rounded),
      ('Private Pool', Icons.pool_rounded),
      ('Air Conditioning', Icons.ac_unit_rounded),
      ('Kitchen', Icons.kitchen_rounded),
      ('Free Parking', Icons.local_parking_rounded),
      ('TV', Icons.tv_rounded),
      ('Washing Machine', Icons.local_laundry_service_rounded),
      ('Gym', Icons.fitness_center_rounded),
      ('Hot Tub / Jacuzzi', Icons.hot_tub_rounded),
      ('Beach Access', Icons.beach_access_rounded),
      ('Garden / Backyard', Icons.yard_rounded),
      ('First Aid Kit', Icons.medical_services_rounded),
    ];

    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  children: [
                    Text(
                      'Tell guests what amenities you offer',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'These are popular amenities guests search for when booking.',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 15, color: AppTheme.muted),
                    ),
                    const SizedBox(height: 36),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final (name, icon) in list)
                          _buildFilterChip(
                            name,
                            icon,
                            _selectedAmenities.contains(name),
                            () {
                              setState(() {
                                if (_selectedAmenities.contains(name)) {
                                  _selectedAmenities.remove(name);
                                } else {
                                  _selectedAmenities.add(name);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 8 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 9: UNIQUENESS TAGS (MAX 4)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep9Uniqueness() {
    final tags = [
      'Mountain View',
      'Private Pool',
      'Lakefront',
      'Ocean View',
      'Peaceful & Quiet',
      'Romantic Getaway',
      'Family Friendly',
      'Workcation Ready',
      'Historic Charm',
      'Lush Greenery',
    ];

    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: [
                    Text(
                      'What makes your place unique?',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink),
                    ),
                    const SizedBox(height: 12),
                    Text('Choose up to 4 tags that best highlight your stay.',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(
                            fontSize: 15, color: AppTheme.muted)),
                    const SizedBox(height: 36),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final tag in tags)
                          ChoiceChip(
                            label: Text(tag,
                                style: AppFonts.sans(
                                    fontWeight: FontWeight.w600)),
                            selected: _selectedUniqueness.contains(tag),
                            selectedColor: AppTheme.sage,
                            onSelected: (selected) {
                              setState(() {
                                if (selected &&
                                    _selectedUniqueness.length < 4) {
                                  _selectedUniqueness.add(tag);
                                } else {
                                  _selectedUniqueness.remove(tag);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 9 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 10: EXPERIENCES (MAX 4)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep10Experiences() {
    final exp = [
      'Bonfire & BBQ',
      'Trekking Guide',
      'Yoga & Meditation',
      'Cooking Classes',
      'Heritage Village Tour',
      'River Rafting',
      'Stargazing',
      'Farm Safari',
    ];

    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: [
                    Text(
                      'Experiences offered on-site',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Experiences must be hosted on-property or within a 5-minute walk.',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 15, color: AppTheme.muted),
                    ),
                    const SizedBox(height: 36),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final item in exp)
                          ChoiceChip(
                            label: Text(item,
                                style: AppFonts.sans(
                                    fontWeight: FontWeight.w600)),
                            selected: _selectedExperiences.contains(item),
                            selectedColor: AppTheme.sage,
                            onSelected: (selected) {
                              setState(() {
                                if (selected &&
                                    _selectedExperiences.length < 4) {
                                  _selectedExperiences.add(item);
                                } else {
                                  _selectedExperiences.remove(item);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 10 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 11: TITLE & DESCRIPTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep11TitleAndDescription() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Give your property a headline & story',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink),
                      ),
                    ),
                    const SizedBox(height: 36),
                    _fieldLabel('Property Headline / Title (max 100 chars)'),
                    TextField(
                      controller: _titleController,
                      decoration: _inputDecoration(
                          'e.g. Seaside Sunset Villa with Private Pool'),
                    ),
                    const SizedBox(height: 24),
                    _fieldLabel('Property Description'),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 4,
                      decoration: _inputDecoration(
                          'Tell guests what makes your place special, nearby attractions, and comfort.'),
                    ),
                    const SizedBox(height: 24),
                    _fieldLabel('YouTube Video or Reel Link (Optional)'),
                    TextField(
                      controller: _videoUrlController,
                      decoration: _inputDecoration(
                          'https://youtube.com/watch?v=... / Instagram reel link'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 11 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 12: NEIGHBOURHOOD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep12Neighbourhood() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Describe the neighbourhood',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'Share details about surroundings, security, nearby cafes, and local attractions.',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(
                            fontSize: 15, color: AppTheme.muted),
                      ),
                    ),
                    const SizedBox(height: 36),
                    _fieldLabel('Neighbourhood & Surroundings'),
                    TextField(
                      controller: _neighbourhoodController,
                      maxLines: 5,
                      decoration: _inputDecoration(
                          'e.g. Located 10 minutes from Lonavala market, secluded on a quiet hill with 24/7 security.'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 12 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 13: PRICE PER NIGHT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep13Pricing() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  children: [
                    Text(
                      'Now, set your base price per night',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'You can adjust seasonal rates and weekend surcharges anytime in your calendar.',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 15, color: AppTheme.muted),
                    ),
                    const SizedBox(height: 48),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 24),
                      decoration: BoxDecoration(
                        color: AppTheme.paper,
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('₹',
                              style: AppFonts.sans(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w800,
                                  color: figmaCoral)),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 180,
                            child: TextField(
                              controller: _priceController,
                              keyboardType: TextInputType.number,
                              style: AppFonts.sans(
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.ink,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: '6500',
                              ),
                            ),
                          ),
                          Text('/ night',
                              style: AppFonts.sans(
                                  fontSize: 18,
                                  color: AppTheme.muted,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 13 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 14: CHECK-IN & CHECK-OUT TIMES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep14CheckInOut() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    Text(
                      'Check-in and check-out schedule',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Give yourself enough time between guest turnovers for cleaning and maintenance.',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 15, color: AppTheme.muted),
                    ),
                    const SizedBox(height: 48),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Check-in Time'),
                              TextField(
                                controller: _checkInController,
                                decoration: _inputDecoration('e.g. 12:00 PM',
                                    prefixText: '🕒 '),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Check-out Time'),
                              TextField(
                                controller: _checkOutController,
                                decoration: _inputDecoration('e.g. 11:00 AM',
                                    prefixText: '🕚 '),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 14 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 15: HOUSE RULES & CANCELLATION POLICY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep15HouseRules() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'House rules & policies',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink),
                      ),
                    ),
                    const SizedBox(height: 36),
                    _buildSwitchTile(
                        'Child-friendly (2–12 yrs)',
                        _childFriendly,
                        (v) => setState(() => _childFriendly = v)),
                    _buildSwitchTile(
                        'Infant-friendly (< 2 yrs)',
                        _infantFriendly,
                        (v) => setState(() => _infantFriendly = v)),
                    _buildSwitchTile('Pets allowed', _petsAllowed,
                        (v) => setState(() => _petsAllowed = v)),
                    _buildSwitchTile('Smoking allowed', _smokingAllowed,
                        (v) => setState(() => _smokingAllowed = v)),
                    _buildSwitchTile(
                        'Parties or events allowed',
                        _partiesAllowed,
                        (v) => setState(() => _partiesAllowed = v)),
                    _buildSwitchTile(
                        'Instant Booking (no pre-approval)',
                        _instantBooking,
                        (v) => setState(() => _instantBooking = v)),
                    const SizedBox(height: 24),
                    _fieldLabel('Cancellation Policy'),
                    Wrap(
                      spacing: 14,
                      runSpacing: 10,
                      children: [
                        ChoiceChip(
                          label: const Text('Flexible (Full refund 24h prior)'),
                          selected: _cancellationPolicy == 'flexible',
                          selectedColor: AppTheme.sage,
                          onSelected: (_) =>
                              setState(() => _cancellationPolicy = 'flexible'),
                        ),
                        ChoiceChip(
                          label:
                              const Text('Moderate (Full refund 5 days prior)'),
                          selected: _cancellationPolicy == 'moderate',
                          selectedColor: AppTheme.sage,
                          onSelected: (_) =>
                              setState(() => _cancellationPolicy = 'moderate'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 15 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 16: CHECK-IN METHOD & CARETAKER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep16CheckInMethod() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Check-in method & on-ground support',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink),
                      ),
                    ),
                    const SizedBox(height: 36),
                    _fieldLabel('How do guests check in?'),
                    Wrap(
                      spacing: 12,
                      children: [
                        ChoiceChip(
                          label:
                              const Text('Host or Caretaker greets in person'),
                          selected: _checkInMethod == 'host_greets',
                          selectedColor: AppTheme.sage,
                          onSelected: (_) =>
                              setState(() => _checkInMethod = 'host_greets'),
                        ),
                        ChoiceChip(
                          label: const Text('Keypad / Smart Lock'),
                          selected: _checkInMethod == 'keypad',
                          selectedColor: AppTheme.sage,
                          onSelected: (_) =>
                              setState(() => _checkInMethod = 'keypad'),
                        ),
                        ChoiceChip(
                          label: const Text('Building Staff / Security'),
                          selected: _checkInMethod == 'staff',
                          selectedColor: AppTheme.sage,
                          onSelected: (_) =>
                              setState(() => _checkInMethod = 'staff'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _fieldLabel('Caretaker / Ground Manager Name'),
                    TextField(
                      controller: _caretakerNameController,
                      decoration: _inputDecoration('e.g. Suresh Patil'),
                    ),
                    const SizedBox(height: 20),
                    _fieldLabel('Caretaker Phone Number'),
                    TextField(
                      controller: _caretakerPhoneController,
                      decoration: _inputDecoration('+91 98765 43210'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 16 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 17: LIVE HOMEYHUTS SCREEN - VERIFY YOUR IDENTITY (QR + MOBILE APP)
  // Exact match to user uploaded screenshot media_1794464144104_697ca614.png
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep17AccountVerification() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.ink.withValues(alpha: 0.04),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pending Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.sage,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.incomplete_circle_outlined,
                                size: 14, color: AppTheme.muted),
                            const SizedBox(width: 6),
                            Text(
                              'Pending',
                              style: AppFonts.sans(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Title
                      Text(
                        'Verify your identity',
                        style: AppFonts.sans(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Subtitle
                      Text(
                        'A quick, one-time check that keeps Bleiben safe for hosts and guests. It only takes about 1 minute.',
                        style: AppFonts.sans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.muted,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Callout Card (Mobile App verification)
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: AppTheme.paper,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Homeyhuts App Icon
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: figmaCoral.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.home_outlined,
                                      color: figmaCoral, size: 24),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Use the Bleiben mobile app to complete profile verification.',
                                        style: AppFonts.sans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'To keep your ID private, we only collect it in our app. All you need is your ID card and a quick selfie.',
                                        style: AppFonts.sans(
                                          fontSize: 13.5,
                                          color: AppTheme.muted,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // QR Code + 3 Steps Row
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth >= 500;
                                final qrWidget = Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 140,
                                      height: 140,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: AppTheme.borderStrong),
                                      ),
                                      child: CustomPaint(
                                        painter: _FigmaQrPainter(),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Works on iPhone and Android',
                                      style: AppFonts.sans(
                                        fontSize: 11.5,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                  ],
                                );

                                final stepsWidget = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildVerifyStep('1',
                                        'Scan the code with your phone camera to get the Bleiben app'),
                                    const SizedBox(height: 14),
                                    _buildVerifyStep('2',
                                        'Sign in with the same account you use here'),
                                    const SizedBox(height: 14),
                                    _buildVerifyStep('3',
                                        'Then open Menu → Profile & Settings → Account Verification'),
                                    const SizedBox(height: 18),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 8,
                                      children: [
                                        _buildAppStoreBadge('App Store'),
                                        _buildAppStoreBadge('Google Play'),
                                      ],
                                    ),
                                  ],
                                );

                                if (isWide) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      qrWidget,
                                      const SizedBox(width: 24),
                                      Expanded(child: stepsWidget),
                                    ],
                                  );
                                } else {
                                  return Column(
                                    children: [
                                      qrWidget,
                                      const SizedBox(height: 20),
                                      stepsWidget,
                                    ],
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 17 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 18: LISTING PREVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep18Preview() {
    final stay = _buildCurrentStay();

    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: [
                    Text(
                      'Preview your listing',
                      style: AppFonts.sans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Here is how guests and OTAs will see your listing once published.',
                      style: AppFonts.sans(
                          fontSize: 15, color: AppTheme.muted),
                    ),
                    const SizedBox(height: 36),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.ink.withValues(alpha: 0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_photos.isNotEmpty)
                            Image.network(
                              _photos.first,
                              height: 260,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 260,
                                width: double.infinity,
                                color: AppTheme.sage,
                                child: const Icon(Icons.image,
                                    size: 48, color: AppTheme.hint),
                              ),
                            )
                          else
                            Container(
                              height: 180,
                              width: double.infinity,
                              color: AppTheme.sage,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.photo_outlined,
                                        size: 40, color: AppTheme.hint),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No photos added yet',
                                      style: AppFonts.sans(
                                          color: AppTheme.hint,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${stay.propertyType} • ${stay.accommodationType == 'entireHouse' ? 'Entire Place' : 'Private Room'}',
                                      style: AppFonts.sans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: figmaCoral),
                                    ),
                                    Text('★ New (0 reviews)',
                                        style: AppFonts.sans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  stay.title.isNotEmpty
                                      ? stay.title
                                      : 'Untitled Listing',
                                  style: AppFonts.sans(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.ink),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  stay.location.isNotEmpty
                                      ? '📍 ${stay.location}'
                                      : '📍 Location not specified',
                                  style: AppFonts.sans(
                                      fontSize: 14,
                                      color: AppTheme.muted),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '${stay.guests} guests • ${stay.bedrooms} bedrooms • ${stay.beds} beds • ${stay.bathrooms} baths',
                                  style: AppFonts.sans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.inkSoft),
                                ),
                                const Divider(height: 32),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            '₹${stay.basePrice.toStringAsFixed(0)}',
                                            style: AppFonts.sans(
                                                fontSize: 24,
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    AppTheme.ink)),
                                        Text('per night (excl. taxes)',
                                            style: AppFonts.sans(
                                                fontSize: 12,
                                                color:
                                                    AppTheme.muted)),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.successSoft,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text('Ready to Activate',
                                          style: TextStyle(
                                              color: AppTheme.success,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 18 / 19, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 19: PUBLISH & BOOK QUICK SETUP CALL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep19Publish() {
    return Column(
      children: [
        _buildFigmaHeaderWithDraft(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: AppTheme.successSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.rocket_launch_rounded,
                            size: 38, color: AppTheme.success),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "You're almost done!",
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your listing is complete. Publish now to start receiving direct bookings and sync your OTAs.',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                          fontSize: 15,
                          color: AppTheme.muted,
                          height: 1.5),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.paper,
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.support_agent_rounded,
                                  color: figmaCoral, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text('Book a Quick Setup Call (Free)',
                                    style: AppFonts.sans(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.ink)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Our hospitality onboarding specialist will connect your Airbnb, Booking.com, and MMT accounts in a 1-on-1 session to eliminate double bookings.',
                            style: AppFonts.sans(
                                fontSize: 13.5, color: AppTheme.muted),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Setup call scheduled!')),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: figmaCoral),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
                            ),
                            child: const Text(
                                'Schedule Call via WhatsApp / Google Meet',
                                style: TextStyle(
                                    color: figmaCoral,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _publish,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: figmaCoral,
                        minimumSize: const Size(280, 54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusButton)),
                        elevation: 6,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text('Publish Listing Now',
                              style: AppFonts.sans(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFigmaStickyFooter(progress: 1.0, backLabel: 'Back'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REUSABLE UI HELPERS & ATOMS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildVerifyStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: AppTheme.sage,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: AppFonts.sans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: figmaCoral,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppFonts.sans(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: AppTheme.inkSoft,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppStoreBadge(String store) {
    final isApple = store == 'App Store';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isApple ? Icons.apple : Icons.play_arrow_rounded,
              color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            isApple ? 'App Store' : 'Google Play',
            style: AppFonts.sans(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.paper : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? figmaCoral : AppTheme.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 32,
                color: isSelected ? figmaCoral : AppTheme.inkSoft),
            const SizedBox(height: 18),
            Text(title,
                style: AppFonts.sans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink)),
            const SizedBox(height: 8),
            Text(subtitle,
                style: AppFonts.sans(
                    fontSize: 13.5,
                    color: AppTheme.muted,
                    height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildCounterRow(
      String label, int value, ValueChanged<int> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppFonts.sans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.ink),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded),
              onPressed: () => onChanged(value - 1),
            ),
            SizedBox(
              width: 36,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: AppFonts.sans(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              color: figmaCoral,
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSwitchTile(
      String title, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title,
            style: AppFonts.sans(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.ink)),
        value: value,
        activeColor: figmaCoral,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFilterChip(
      String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.sage : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isSelected ? figmaCoral : AppTheme.borderStrong,
              width: isSelected ? 1.8 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 20,
                color: isSelected ? figmaCoral : AppTheme.inkSoft),
            const SizedBox(width: 8),
            Text(label,
                style: AppFonts.sans(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? figmaCoral : AppTheme.ink)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceTypeCard({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onSelect,
  }) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 214),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.paper : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? figmaCoral : AppTheme.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? figmaCoral.withOpacity(0.08)
                  : AppTheme.ink.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? figmaCoral.withOpacity(0.12)
                        : AppTheme.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon,
                      size: 26,
                      color: isSelected ? figmaCoral : AppTheme.ink),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? figmaCoral : AppTheme.borderStrong,
                      width: isSelected ? 6 : 1.5,
                    ),
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: AppFonts.sans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isSelected ? figmaCoral : AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppFonts.sans(
                fontSize: 13.5,
                color: AppTheme.muted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationPill(String location) {
    final isSelected = _locationController.text.trim() == location;
    return InkWell(
      onTap: () {
        setState(() {
          _locationController.text = location;
          final parts = location.split(',');
          if (parts.isNotEmpty) _cityController.text = parts[0].trim();
          if (parts.length > 1) _stateController.text = parts[1].trim();
        });
      },
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.sage : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(
            color: isSelected ? figmaCoral : AppTheme.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 15,
              color: isSelected ? figmaCoral : AppTheme.muted,
            ),
            const SizedBox(width: 6),
            Text(
              location,
              style: AppFonts.sans(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? figmaCoral : AppTheme.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFigmaHeaderWithDraft() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.sage)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const BleibenWordmark(),
          Row(
            children: [
              OutlinedButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        await _persistStep();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Draft saved successfully!')),
                          );
                        }
                      },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(120, 38),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  side: const BorderSide(color: figmaCoral, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  ),
                ),
                child: Text(
                  _isSaving ? 'Saving...' : 'Save as Draft',
                  style: AppFonts.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: figmaCoral,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              InkWell(
                onTap: () async {
                  final action = await showAccountSheet(
                    context,
                    signedIn: true,
                    displayName: 'Host Account',
                  );
                  if (action == AccountAction.logout && mounted) {
                    Navigator.of(context).pop();
                  }
                },
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(5, 4, 12, 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppTheme.ink,
                        child: Text(
                          'A',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        Icons.menu_rounded,
                        size: 20,
                        color: AppTheme.ink,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFigmaStickyFooter({
    required double progress,
    String backLabel = 'Back',
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.sage)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: AppTheme.border,
            valueColor: const AlwaysStoppedAnimation(figmaCoral),
            minHeight: 4,
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _back,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.inkSoft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: Text(
                      backLabel,
                      style: AppFonts.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: figmaCoral,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size(120, 48),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 36, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Text(
                            _currentStep == _totalSteps - 1
                                ? 'Publish'
                                : 'Next',
                            style: AppFonts.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Common input decoration & label
  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppFonts.sans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.ink,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, {String? prefixText}) {
    return InputDecoration(
      hintText: hint,
      prefixText: prefixText,
      hintStyle:
          AppFonts.sans(color: AppTheme.hint, fontSize: 14),
      filled: true,
      fillColor: AppTheme.paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: figmaCoral, width: 1.5),
      ),
    );
  }

  // Step 0 Specific Widgets
  Widget _buildFigmaMainHeader() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.sage)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const BleibenWordmark(),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              side: const BorderSide(color: AppTheme.borderStrong),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
            ),
            child: Text(
              'Exit to home',
              style: AppFonts.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFigmaSetupProgress() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 640;
        final steps = [
          ('1', 'Add Your Property', true),
          ('2', 'Complete Your Listing', false),
          ('3', 'Connect Your OTAs', false),
        ];

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: AppTheme.paper,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: isDesktop
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (int i = 0; i < steps.length; i++) ...[
                      if (i > 0)
                        Container(
                          width: 40,
                          height: 1,
                          color: AppTheme.borderStrong,
                        ),
                      _buildProgressStepItem(
                          steps[i].$1, steps[i].$2, steps[i].$3),
                    ],
                  ],
                )
              : Column(
                  children: [
                    for (int i = 0; i < steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _buildProgressStepItem(
                            steps[i].$1, steps[i].$2, steps[i].$3),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildProgressStepItem(String number, String label, bool isActive) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? figmaCoral : AppTheme.border,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.white : AppTheme.muted,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppFonts.sans(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? AppTheme.ink : AppTheme.muted,
          ),
        ),
      ],
    );
  }

  Widget _buildCardAirbnb() {
    return _buildMethodCard(
      method: 'airbnb',
      title: 'Import from Airbnb',
      description:
          'Fastest setup. Connect your Airbnb account to import all photos, titles, and property details automatically.',
      icon: Icons.sync_rounded,
      badge: 'Fastest',
      iconBgColor: AppTheme.sage,
      iconColor: figmaCoral,
    );
  }

  Widget _buildCardManual() {
    return _buildMethodCard(
      method: 'manual',
      title: 'Create Manually',
      description:
          'Build your listing step by step. Add property photos, custom amenities, pricing rules, and location manually.',
      icon: Icons.edit_note_rounded,
      iconBgColor: AppTheme.sage,
      iconColor: AppTheme.ink,
    );
  }

  Widget _buildCardClone() {
    return _buildMethodCard(
      method: 'clone',
      title: 'Clone a Bleiben property',
      description:
          'Duplicate an existing property listing and adjust details for a new villa, cottage, or room.',
      icon: Icons.copy_rounded,
      iconBgColor: AppTheme.sage,
      iconColor: AppTheme.ink,
    );
  }

  Widget _buildMethodCard({
    required String method,
    required String title,
    required String description,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    String? badge,
  }) {
    final isSelected = _setupMethod == method;
    return InkWell(
      onTap: () => setState(() => _setupMethod = method),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 200),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.paper : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? figmaCoral : AppTheme.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.successSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(badge,
                        style: const TextStyle(
                            color: AppTheme.success,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(title,
                style: AppFonts.sans(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink)),
            const SizedBox(height: 8),
            Text(description,
                style: AppFonts.sans(
                    fontSize: 13,
                    color: AppTheme.muted,
                    height: 1.45)),
          ],
        ),
      ),
    );
  }

  String _getStep0ButtonText() {
    if (_setupMethod == 'airbnb') return 'Import from Airbnb';
    if (_setupMethod == 'clone') return 'Clone selected property';
    return 'Continue to create manually';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM MAP PAINTER (FIGMA 17:139)
// ═══════════════════════════════════════════════════════════════════════════

class _FigmaMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = AppTheme.successSoft;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final dotPaint = Paint()..color = AppTheme.successSoft;
    const spacing = 26.0;
    for (double x = 12; x < size.width; x += spacing) {
      for (double y = 12; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 2.2, dotPaint);
      }
    }

    final blueRoadPaint = Paint()
      ..color = const Color(0xFF5B8FB9)
      ..strokeWidth = 3.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final bluePath = Path();
    bluePath.moveTo(size.width * 0.38, 0);
    bluePath.quadraticBezierTo(
      size.width * 0.42,
      size.height * 0.45,
      size.width * 0.47,
      size.height * 0.78,
    );
    bluePath.lineTo(size.width * 0.49, size.height);
    canvas.drawPath(bluePath, blueRoadPaint);

    final tanRoadPaint = Paint()
      ..color = const Color(0xFFD89B55)
      ..strokeWidth = 3.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final tanPath = Path();
    tanPath.moveTo(size.width * 0.53, size.height * 0.74);
    tanPath.quadraticBezierTo(
      size.width * 0.49,
      size.height * 0.76,
      size.width * 0.45,
      size.height * 0.82,
    );
    tanPath.lineTo(size.width * 0.38, size.height);
    canvas.drawPath(tanPath, tanRoadPaint);

    final whiteRoadPaint = Paint()
      ..color = Colors.white.withOpacity(0.92)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final whitePath = Path();
    whitePath.moveTo(0, size.height * 0.84);
    whitePath.cubicTo(
      size.width * 0.28,
      size.height * 0.82,
      size.width * 0.68,
      size.height * 0.88,
      size.width,
      size.height * 0.78,
    );
    canvas.drawPath(whitePath, whiteRoadPaint);

    _drawShield(canvas, Offset(size.width * 0.44, size.height * 0.61), '44');
    _drawShield(canvas, Offset(size.width * 0.70, size.height * 0.61), '258');
    _drawShield(canvas, Offset(size.width * 0.45, size.height * 0.92), '347A');

    _drawLabel(
        canvas, Offset(size.width * 0.47, size.height * 0.65), 'RENKAPUR',
        isBold: true);
    _drawLabel(canvas, Offset(size.width * 0.63, size.height * 0.58),
        'Waygaon (H)\nवायगांव');
    _drawLabel(
        canvas, Offset(size.width * 0.45, size.height * 0.85), 'Jamb\nजांब');
    _drawLabel(canvas, Offset(size.width * 0.60, size.height * 0.95),
        'Chikhalkot\nचिखलकोट');
  }

  void _drawShield(Canvas canvas, Offset center, String text) {
    final shieldPaint = Paint()..color = const Color(0xFFFACC15);
    final width = text.length > 2 ? 38.0 : 26.0;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: 20.0),
      const Radius.circular(4),
    );
    canvas.drawRRect(rrect, shieldPaint);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: AppTheme.ink,
            fontSize: 10.5,
            fontWeight: FontWeight.w800),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawLabel(Canvas canvas, Offset offset, String text,
      {bool isBold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: AppTheme.inkSoft,
          fontSize: 11,
          fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
          height: 1.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM QR CODE PAINTER (STEP 17 - VERIFY YOUR IDENTITY)
// ═══════════════════════════════════════════════════════════════════════════

class _FigmaQrPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppTheme.ink;

    // Corner Finder Patterns (Top-Left, Top-Right, Bottom-Left)
    _drawFinder(canvas, const Offset(6, 6), p);
    _drawFinder(canvas, Offset(size.width - 34, 6), p);
    _drawFinder(canvas, Offset(6, size.height - 34), p);

    // Matrix Dots
    const dot = 4.0;
    for (double y = 6; y < size.height - 6; y += 8) {
      for (double x = 6; x < size.width - 6; x += 8) {
        if ((x < 36 && y < 36) ||
            (x > size.width - 40 && y < 36) ||
            (x < 36 && y > size.height - 40)) {
          continue;
        }
        if ((x * y).toInt() % 7 < 3) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, dot, dot), const Radius.circular(1)),
            p,
          );
        }
      }
    }
  }

  void _drawFinder(Canvas canvas, Offset origin, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(origin.dx, origin.dy, 28, 28),
          const Radius.circular(4)),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(origin.dx + 4, origin.dy + 4, 20, 20),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(origin.dx + 8, origin.dy + 8, 12, 12),
          const Radius.circular(2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
