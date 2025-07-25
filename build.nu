print "Hello from nushell!"
mkdir ($env.PREFIX | path join "test")
print "Test directory created successfully"
