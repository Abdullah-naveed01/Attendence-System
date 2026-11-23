// =====================================================================
// Supabase Edge Function: manage-teacher
//
// Lets an ADMIN create/remove teachers and add/delete students.
// Creating/deleting login accounts needs the service_role key. That key
// exists ONLY here on the Supabase server (Supabase provides it to every
// Edge Function as SUPABASE_SERVICE_ROLE_KEY). It is never in the app.
//
// Deployed in Supabase under the name "rapid-task".
// The app calls:  supabase.functions.invoke('rapid-task', body: {...})
//
//   Teachers
//   Create: { action: 'create', full_name, email, password,
//             courses: [ { course_id } | { new_course: { name, code, semester } } ] }
//   Remove: { action: 'remove', teacher_id }
//
//   Students (all students are in the same class: they get every course
//   that appears in the timetable)
//   Add:          { action: 'add_student', full_name, email, password }
//   Enroll all:   { action: 'enroll_all', student_id }
//   Delete:       { action: 'delete_student', student_id }
//
// Every answer is JSON: { ok: true, code } or { ok: false, code, message }
// =====================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

// Allows the app to call this function from a web browser too (Chrome testing).
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Server-side client with full rights (service_role). Never sent to the app.
const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

const EMAIL_PATTERN = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function fail(status: number, code: string, message: string): Response {
  return reply(status, { ok: false, code, message });
}

Deno.serve(async (req) => {
  // Browser "pre-flight" check
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return fail(405, "METHOD_NOT_ALLOWED", "Use POST.");
  }

  try {
    // ---------- 1. Who is calling? (check the caller's login token) ----------
    const token = (req.headers.get("Authorization") ?? "")
      .replace(/^Bearer\s+/i, "");
    if (!token) {
      return fail(401, "NOT_AUTHENTICATED", "Please log in again.");
    }
    const { data: userData, error: userError } = await admin.auth.getUser(
      token,
    );
    if (userError || !userData?.user) {
      return fail(401, "NOT_AUTHENTICATED", "Please log in again.");
    }
    const callerId = userData.user.id;

    // ---------- 2. Is the caller an admin? Otherwise 403 ----------
    const { data: callerProfile, error: roleError } = await admin
      .from("profiles")
      .select("role")
      .eq("id", callerId)
      .maybeSingle();
    if (roleError) throw roleError;
    if (callerProfile?.role !== "admin") {
      return fail(
        403,
        "NOT_ADMIN",
        "Only an admin can manage teachers and students.",
      );
    }

    // ---------- 3. Do the requested action ----------
    const body = await req.json().catch(() => null);
    if (!body || typeof body !== "object") {
      return fail(400, "INVALID_INPUT", "The request must be JSON.");
    }
    switch (body.action) {
      case "create":
        return await createTeacher(body);
      case "remove":
        return await removeTeacher(body, callerId);
      case "add_student":
        return await addStudent(body);
      case "enroll_all":
        return await enrollInAllClassCourses(body);
      case "delete_student":
        return await deleteStudent(body, callerId);
      default:
        return fail(400, "INVALID_INPUT", "Unknown action.");
    }
  } catch (error) {
    console.error(error);
    // Database errors are plain objects with a "message" field, not Error
    // objects, so read the message from either kind.
    // deno-lint-ignore no-explicit-any
    const message = (error as any)?.message ?? JSON.stringify(error);
    return fail(500, "SERVER_ERROR", message);
  }
});

// =====================================================================
// CREATE: new login account + teacher profile + courses
// Everything is checked BEFORE the account is created, so a mistake
// never leaves a half-made teacher behind.
// =====================================================================
// deno-lint-ignore no-explicit-any
async function createTeacher(body: any): Promise<Response> {
  const fullName = String(body.full_name ?? "").trim();
  const email = String(body.email ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  const choices = Array.isArray(body.courses) ? body.courses : [];

  // --- Check the form values ---
  if (fullName.length < 2) {
    return fail(400, "INVALID_INPUT", "Full name is required.");
  }
  if (!EMAIL_PATTERN.test(email)) {
    return fail(400, "INVALID_INPUT", "Enter a valid email address.");
  }
  if (password.length < 8) {
    return fail(400, "INVALID_INPUT", "Password must be at least 8 characters.");
  }
  if (choices.length === 0) {
    return fail(400, "INVALID_INPUT", "Assign at least one course.");
  }

  // --- Split the courses into "existing" and "new" ---
  const existingIds: string[] = [];
  const newCourses: { name: string; code: string; semester: string }[] = [];
  for (const choice of choices) {
    if (choice?.course_id) {
      existingIds.push(String(choice.course_id));
    } else if (choice?.new_course) {
      const name = String(choice.new_course.name ?? "").trim();
      const code = String(choice.new_course.code ?? "").trim().toUpperCase();
      const semester = String(choice.new_course.semester ?? "").trim();
      if (!name || !code || !semester) {
        return fail(
          400,
          "INVALID_INPUT",
          "Each new course needs a name, a code and a semester.",
        );
      }
      newCourses.push({ name, code, semester });
    } else {
      return fail(400, "INVALID_INPUT", "Each course must be existing or new.");
    }
  }

  // --- New course codes must be unique (in this form and in the database) ---
  const codes = newCourses.map((c) => c.code);
  if (new Set(codes).size !== codes.length) {
    return fail(409, "COURSE_CODE_EXISTS", "The same course code is used twice.");
  }
  if (codes.length > 0) {
    const { data: taken, error } = await admin
      .from("courses")
      .select("code")
      .in("code", codes);
    if (error) throw error;
    if (taken.length > 0) {
      return fail(
        409,
        "COURSE_CODE_EXISTS",
        `Course code already exists: ${taken.map((c) => c.code).join(", ")}`,
      );
    }
  }

  // --- Existing courses must really exist ---
  const uniqueIds = [...new Set(existingIds)];
  if (uniqueIds.length > 0) {
    if (!uniqueIds.every((id) => UUID_PATTERN.test(id))) {
      return fail(400, "COURSE_NOT_FOUND", "One of the courses was not found.");
    }
    const { data: found, error } = await admin
      .from("courses")
      .select("id")
      .in("id", uniqueIds);
    if (error) throw error;
    if (found.length !== uniqueIds.length) {
      return fail(400, "COURSE_NOT_FOUND", "One of the courses was not found.");
    }
  }

  // --- Create the login account (already confirmed, can log in at once) ---
  const { data: created, error: createError } = await admin.auth.admin
    .createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    });
  if (createError || !created?.user) {
    if (/already|registered|exists/i.test(createError?.message ?? "")) {
      return fail(409, "EMAIL_EXISTS", "An account with this email already exists.");
    }
    throw createError ?? new Error("Could not create the account.");
  }
  const teacherId = created.user.id;
  const createdCourseIds: string[] = [];

  try {
    // Profile: the signup trigger creates it as 'student' -> make it 'teacher'
    const { error: profileError } = await admin.from("profiles").upsert(
      { id: teacherId, email, full_name: fullName, role: "teacher" },
      { onConflict: "id" },
    );
    if (profileError) throw profileError;

    // New courses, owned by this teacher
    if (newCourses.length > 0) {
      const { data: inserted, error } = await admin
        .from("courses")
        .insert(newCourses.map((c) => ({ ...c, teacher_id: teacherId })))
        .select("id");
      if (error) throw error;
      createdCourseIds.push(...inserted.map((c) => c.id));
    }

    // Existing courses: move them to this teacher
    if (uniqueIds.length > 0) {
      const { error } = await admin
        .from("courses")
        .update({ teacher_id: teacherId })
        .in("id", uniqueIds);
      if (error) throw error;
    }
  } catch (error) {
    // Something failed: undo, so no half-made teacher stays behind.
    if (createdCourseIds.length > 0) {
      await admin.from("courses").delete().in("id", createdCourseIds);
    }
    await admin.from("profiles").delete().eq("id", teacherId);
    await admin.auth.admin.deleteUser(teacherId);
    throw error;
  }

  return reply(200, { ok: true, code: "CREATED", teacher_id: teacherId });
}

// =====================================================================
// REMOVE: unassign courses (keep all attendance), then delete the account
// =====================================================================
// deno-lint-ignore no-explicit-any
async function removeTeacher(body: any, callerId: string): Promise<Response> {
  const teacherId = String(body.teacher_id ?? "");
  if (!UUID_PATTERN.test(teacherId)) {
    return fail(400, "INVALID_INPUT", "teacher_id is missing or wrong.");
  }
  if (teacherId === callerId) {
    return fail(400, "INVALID_INPUT", "You cannot remove your own account.");
  }

  // Only teachers can be removed here (never students or admins)
  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("role")
    .eq("id", teacherId)
    .maybeSingle();
  if (profileError) throw profileError;
  if (!profile) {
    return fail(404, "NOT_FOUND", "This teacher no longer exists.");
  }
  if (profile.role !== "teacher") {
    return fail(400, "NOT_A_TEACHER", "This account is not a teacher.");
  }

  // 1. Unassign their courses. Courses, sessions and attendance all stay.
  const { error: unassignError } = await admin
    .from("courses")
    .update({ teacher_id: null })
    .eq("teacher_id", teacherId);
  if (unassignError) throw unassignError;

  // 2. A teacher should have no student enrollments; remove any leftovers.
  const { error: enrollError } = await admin
    .from("enrollments")
    .delete()
    .eq("student_id", teacherId);
  if (enrollError) throw enrollError;

  // 3. Remove the profile, then the login account.
  const { error: deleteProfileError } = await admin
    .from("profiles")
    .delete()
    .eq("id", teacherId);
  if (deleteProfileError) throw deleteProfileError;

  const { error: deleteUserError } = await admin.auth.admin.deleteUser(
    teacherId,
  );
  if (deleteUserError) throw deleteUserError;

  return reply(200, { ok: true, code: "REMOVED" });
}

// =====================================================================
// STUDENTS
// All students are in the same class, so every student is enrolled in
// every course that appears in the timetable ("class courses").
// =====================================================================

// The ids of every course that has at least one timetable slot.
async function classCourseIds(): Promise<string[]> {
  const { data, error } = await admin.from("timetable").select("course_id");
  if (error) throw error;
  return [...new Set(data.map((row) => row.course_id as string))];
}

// Enrolls one student in all class courses. Existing enrollments are
// skipped (UNIQUE(student_id, course_id)). Returns how many were added.
async function enrollStudent(studentId: string): Promise<number> {
  const courseIds = await classCourseIds();

  const { data: existing, error: existingError } = await admin
    .from("enrollments")
    .select("course_id")
    .eq("student_id", studentId);
  if (existingError) throw existingError;
  const already = new Set(existing.map((row) => row.course_id as string));

  const missing = courseIds.filter((id) => !already.has(id));
  if (missing.length === 0) return 0;

  const { error } = await admin
    .from("enrollments")
    .insert(missing.map((courseId) => ({
      student_id: studentId,
      course_id: courseId,
    })));
  if (error) throw error;
  return missing.length;
}

// Loads a profile and checks it is a student (never a teacher or admin).
async function requireStudent(
  studentId: string,
): Promise<Response | null> {
  if (!UUID_PATTERN.test(studentId)) {
    return fail(400, "INVALID_INPUT", "student_id is missing or wrong.");
  }
  const { data: profile, error } = await admin
    .from("profiles")
    .select("role")
    .eq("id", studentId)
    .maybeSingle();
  if (error) throw error;
  if (!profile) {
    return fail(404, "NOT_FOUND", "This student no longer exists.");
  }
  if (profile.role !== "student") {
    return fail(400, "NOT_A_STUDENT", "This account is not a student.");
  }
  return null; // OK
}

// ---------- ADD STUDENT: login account + student profile + class courses ----------
// deno-lint-ignore no-explicit-any
async function addStudent(body: any): Promise<Response> {
  const fullName = String(body.full_name ?? "").trim();
  const email = String(body.email ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");

  // Check everything BEFORE creating the account
  if (fullName.length < 2) {
    return fail(400, "INVALID_INPUT", "Full name is required.");
  }
  if (!EMAIL_PATTERN.test(email)) {
    return fail(400, "INVALID_INPUT", "Enter a valid email address.");
  }
  if (password.length < 8) {
    return fail(400, "INVALID_INPUT", "Password must be at least 8 characters.");
  }
  if ((await classCourseIds()).length === 0) {
    return fail(
      400,
      "NO_CLASS_COURSES",
      "The timetable has no courses yet, so there is nothing to enroll in.",
    );
  }

  // Create the login account (already confirmed, can log in at once)
  const { data: created, error: createError } = await admin.auth.admin
    .createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    });
  if (createError || !created?.user) {
    if (/already|registered|exists/i.test(createError?.message ?? "")) {
      return fail(409, "EMAIL_EXISTS", "An account with this email already exists.");
    }
    throw createError ?? new Error("Could not create the account.");
  }
  const studentId = created.user.id;

  try {
    // Profile: role 'student' with the full name
    const { error: profileError } = await admin.from("profiles").upsert(
      { id: studentId, email, full_name: fullName, role: "student" },
      { onConflict: "id" },
    );
    if (profileError) throw profileError;

    const enrolled = await enrollStudent(studentId);
    return reply(200, {
      ok: true,
      code: "CREATED",
      student_id: studentId,
      courses_enrolled: enrolled,
    });
  } catch (error) {
    // Something failed: undo, so no half-made student stays behind.
    await admin.from("enrollments").delete().eq("student_id", studentId);
    await admin.from("profiles").delete().eq("id", studentId);
    await admin.auth.admin.deleteUser(studentId);
    throw error;
  }
}

// ---------- ENROLL ALL: add the class courses a student is missing ----------
// deno-lint-ignore no-explicit-any
async function enrollInAllClassCourses(body: any): Promise<Response> {
  const studentId = String(body.student_id ?? "");
  const problem = await requireStudent(studentId);
  if (problem) return problem;

  const added = await enrollStudent(studentId);
  return reply(200, { ok: true, code: "ENROLLED", courses_enrolled: added });
}

// ---------- DELETE STUDENT (permanent) ----------
// The deleting itself is done by the SQL function admin_delete_student
// (sql/admin_students.sql) in ONE transaction: attendance, enrollments,
// profile, login account. If any step fails, nothing is deleted.
// deno-lint-ignore no-explicit-any
async function deleteStudent(body: any, callerId: string): Promise<Response> {
  const studentId = String(body.student_id ?? "");
  if (studentId === callerId) {
    return fail(400, "INVALID_INPUT", "You cannot delete your own account.");
  }
  const problem = await requireStudent(studentId);
  if (problem) return problem;

  const { data, error } = await admin.rpc("admin_delete_student", {
    p_student_id: studentId,
  });
  if (error) throw error;
  if (!data?.ok) {
    return fail(400, String(data?.code ?? "SERVER_ERROR"), "Could not delete the student.");
  }
  return reply(200, {
    ok: true,
    code: "DELETED",
    attendance_deleted: data.attendance_deleted ?? 0,
  });
}
