void test() {
  auto ev = getenv("EVENT");
  // foo(strlen(ev->parameter));
  char *p = new char[strlen(ev->parameter)];
  // ok: test
  sink(ev->parameter);
  return p;
}
