class Patient {
  final int? id;
  final String fullName;
  final String dob;
  final String address;
  final String phone;
  final String complaint;

  Patient({
    this.id,
    required this.fullName,
    required this.dob,
    required this.address,
    required this.phone,
    required this.complaint,
  });

  // Convert a patient into a Map object for SQLite
  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'dob': dob,
      'address': address,
      'phone': phone,
      'complaint': complaint,
    };
  }

  // Convert a Map object into a patient
  factory Patient.fromMap(Map<String, dynamic> map) {
    return Patient(
      id: map['id'],
      fullName: map['fullName'],
      dob: map['dob'],
      address: map['address'],
      phone: map['phone'],
      complaint: map['complaint'],
    );
  }
}
