import textwrap
import unittest

from src.odin_clj import translate


class TranslateTests(unittest.TestCase):
    def test_hello_program(self) -> None:
        source = textwrap.dedent(
            """
            (package main)
            (import "core:fmt")
            (proc main [] void
              (fmt.println "hello")
              (let x int 41)
              (fmt.println (+ x 1)))
            """
        )

        self.assertEqual(
            translate(source),
            textwrap.dedent(
                """\
                package main

                import "core:fmt"

                main :: proc() {
                    fmt.println("hello")
                    x: int = 41
                    fmt.println(x + 1)
                }
                """
            ),
        )

    def test_control_flow(self) -> None:
        source = textwrap.dedent(
            """
            (proc main [] void
              (for [(let i int 0) (< i 3) (+= i 1)]
                (if (== i 1)
                  (fmt.println "one")
                  (fmt.println "other"))))
            """
        )

        self.assertIn("for i: int = 0; i < 3; i += 1", translate(source))
        self.assertIn('fmt.println("one")', translate(source))


if __name__ == "__main__":
    unittest.main()
