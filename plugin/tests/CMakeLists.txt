add_executable(codexpricing-test
    codexpricing_test.cpp
    ../src/Caelestia/Services/codexpricing.cpp
)

target_include_directories(codexpricing-test PRIVATE ../src/Caelestia/Services)
target_link_libraries(codexpricing-test PRIVATE Qt::Core)

add_test(NAME codexpricing COMMAND codexpricing-test)
