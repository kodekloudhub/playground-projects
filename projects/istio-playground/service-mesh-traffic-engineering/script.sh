if kubectl exec client-test -c client-test -- curl -sS --connect-timeout 3 "http://$POD_IP" > /home/admin/plaintext-attempt.txt 2>&1; then
  echo "Unexpected HTTP response:"
  cat /home/admin/plaintext-attempt.txt
else
  echo "Plaintext request rejected as expected"
fi
cat /home/admin/plaintext-attempt.txt
