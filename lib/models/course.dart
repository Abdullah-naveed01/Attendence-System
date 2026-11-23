// Holds one row of the courses table as a Dart object.
class Course {
  final String id;
  final String name;
  final String code;
  final String semester;
  final String? teacherId;

  Course({
    required this.id,
    required this.name,
    required this.code,
    required this.semester,
    this.teacherId,
  });

  // Converts the Map returned by Supabase into a Course object.
  factory Course.fromMap(Map<String, dynamic> map) {
    return Course(
      id: map['id'] as String,
      name: (map['name'] ?? '') as String,
      code: (map['code'] ?? '') as String,
      // semester may be stored as a number or text; we keep it as text.
      semester: (map['semester'] ?? '').toString(),
      teacherId: map['teacher_id'] as String?,
    );
  }
}
