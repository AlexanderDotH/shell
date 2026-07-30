add_executable(codexpricing-test
    codexpricing_test.cpp
    ../src/Caelestia/Services/codexpricing.cpp
)

target_include_directories(codexpricing-test PRIVATE ../src/Caelestia/Services)
target_link_libraries(codexpricing-test PRIVATE Qt::Core)

add_test(NAME codexpricing COMMAND codexpricing-test)

add_executable(codexratewindows-test
    codexratewindows_test.cpp
    ../src/Caelestia/Services/codexratewindows.cpp
)

target_include_directories(codexratewindows-test PRIVATE ../src/Caelestia/Services)
target_link_libraries(codexratewindows-test PRIVATE Qt::Core)

add_test(NAME codexratewindows COMMAND codexratewindows-test)

add_executable(codexresetcredits-test
    codexresetcredits_test.cpp
    ../src/Caelestia/Services/codexresetcredits.cpp
)

target_include_directories(codexresetcredits-test PRIVATE ../src/Caelestia/Services)
target_link_libraries(codexresetcredits-test PRIVATE Qt::Core)

add_test(NAME codexresetcredits COMMAND codexresetcredits-test)

add_executable(requests-test
    requests_test.cpp
    ../src/Caelestia/requests.cpp
    ../src/Caelestia/requests.hpp
)

target_include_directories(requests-test PRIVATE ../src/Caelestia)
target_link_libraries(requests-test PRIVATE Qt::Core Qt::Qml Qt::Network)

add_test(NAME requests COMMAND requests-test)
set_tests_properties(requests PROPERTIES TIMEOUT 10)
