import 'package:get_it/get_it.dart';

/// سرویس‌یاب مرکزی برای مدیریت وابستگی‌ها (Dependency Injection)
///
/// ## فلسفه طراحی
///
/// این کلاس یک wrapper نوع-ایمن (type-safe) حول کتابخانه `get_it`
/// است و به عنوان singleton container مرکزی برای تمام سرویس‌های پروژه
/// عمل می‌کند.
///
/// ## مزایا
///
/// - **جداسازی وابستگی**: کدهای پروژه به جای وابستگی مستقیم به `get_it`
///   فقط به `ServiceLocator` وابسته هستند. در صورت تغییر کتابخانه DI،
///   فقط این کلاس تغییر می‌کند.
/// - **Type Safety**: تمام متدها generic هستند و بازگشت نوع مطمئن را تضمین می‌کنند.
/// - **ثبت متمرکز**: تمام سرویس‌ها در `InjectionContainer.initialize()`
///   ثبت می‌شوند. دسترسی تصادفی به سرویس‌های ثبت‌نشده در زمان کامپایل
///   قابل شناسایی نیست ولی در زمان اجرا خطای شفاف می‌دهد.
///
/// ## ترتیب مقداردهی
///
/// 1. در `main()` ابتدا `InjectionContainer.initialize()` فراخوانی می‌شود
/// 2. سپس سایر سرویس‌ها از طریق `ServiceLocator.get<T>()` قابل دسترسی هستند
/// 3. برای بازنشانی (مثلاً در تست‌ها) از `ServiceLocator.reset()` استفاده کنید
///
/// ## مثال
///
/// ```dart
/// // ثبت سرویس (در InjectionContainer)
/// ServiceLocator.registerSingleton<SecureStorage>(() => SecureStorage());
///
/// // دسترسی به سرویس
/// final storage = ServiceLocator.get<SecureStorage>();
/// ```
class ServiceLocator {
  ServiceLocator._();

  /// Instance اصلی `get_it` که تمام سرویس‌ها در آن ثبت می‌شوند
  static final GetIt _getIt = GetIt.instance;

  /// دریافت یک سرویس ثبت‌شده از DI container
  ///
  /// سرویس باید قبلاً با `registerSingleton` یا `registerLazySingleton`
  /// ثبت شده باشد. در غیر این صورت `DependencyNotFoundException` پرتاب می‌کند.
  ///
  /// Example:
  /// ```dart
  /// final storage = ServiceLocator.get<SecureStorage>();
  /// final auth = ServiceLocator.get<ClientAuthService>();
  /// ```
  static T get<T extends Object>() {
    return _getIt<T>();
  }

  /// دریافت یک سرویس ثبت‌شده، یا `null` اگر ثبت نشده باشد
  ///
  /// برخلاف [get] که در صورت عدم ثبت خطا می‌دهد، این متد `null` برمی‌گرداند.
  /// مناسب برای سناریوهایی که سرویس ممکن است اختیاری باشد.
  ///
  /// Example:
  /// ```dart
  /// final service = ServiceLocator.maybeGet<OptionalService>();
  /// if (service != null) { ... }
  /// ```
  static T? maybeGet<T extends Object>() {
    if (_getIt.isRegistered<T>()) {
      return _getIt<T>();
    }
    return null;
  }

  /// ثبت یک singleton سرویس
  ///
  /// سرویس **بلافاصله** نمونه‌سازی می‌شود (eager singleton) و تا پایان
  /// عمر برنامه یک instance واحد خواهد داشت. برای سرویس‌هایی که در
  /// همان ابتدای کار به آنها نیاز است از این متد استفاده کنید.
  ///
  /// Example:
  /// ```dart
  /// ServiceLocator.registerSingleton<SecureStorage>(() => SecureStorage());
  /// ```
  static void registerSingleton<T extends Object>(
    T Function() factory,
  ) {
    _getIt.registerSingleton<T>(factory());
  }

  /// ثبت یک lazy singleton سرویس
  ///
  /// سرویس در **اولین دسترسی** نمونه‌سازی می‌شود (lazy singleton).
  /// مناسب برای سرویس‌هایی که ممکن است در طول عمر برنامه استفاده نشوند
  /// یا مقداردهی اولیه سنگینی دارند.
  ///
  /// Example:
  /// ```dart
  /// ServiceLocator.registerLazySingleton<BalanceManager>(
  ///   () => BalanceManager(),
  /// );
  /// ```
  static void registerLazySingleton<T extends Object>(
    T Function() factory,
  ) {
    _getIt.registerLazySingleton<T>(factory);
  }

  /// ثبت یک singleton با استفاده از instance موجود
  ///
  /// این متد برای مواردی استفاده می‌شود که نیاز به ثبت یک instance
  /// تحت یک interface داریم. مثال:
  ///
  /// ```dart
  /// final storage = SecureStorage();
  /// ServiceLocator.registerSingleton<SecureStorage>(() => storage);
  /// ServiceLocator.registerSingletonWithInstance<IWalletDataSource>(storage);
  /// ```
  static void registerSingletonWithInstance<T extends Object>(
    T instance,
  ) {
    _getIt.registerSingleton<T>(instance);
  }

  /// بررسی می‌کند که آیا یک سرویس با نوع مشخص ثبت شده است یا خیر
  ///
  /// Example:
  /// ```dart
  /// if (ServiceLocator.isRegistered<SecureStorage>()) {
  ///   final storage = ServiceLocator.get<SecureStorage>();
  /// }
  /// ```
  static bool isRegistered<T extends Object>() {
    return _getIt.isRegistered<T>();
  }

  /// بازنشانی همه سرویس‌های ثبت‌شده
  ///
  /// ⚠️ **فقط در تست‌ها و شرایط خاص استفاده شود**.
  /// پس از فراخوانی این متد، تمام سرویس‌ها پاک می‌شوند و
  /// `InjectionContainer.initialize()` باید دوباره فراخوانی شود.
  ///
  /// Example:
  /// ```dart
  /// setUp(() async {
  ///   ServiceLocator.reset();
  ///   await InjectionContainer.initialize();
  /// });
  /// ```
  static void reset() {
    _getIt.reset();
  }
}
